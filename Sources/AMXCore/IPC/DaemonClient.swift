import Foundation

public enum DaemonClientError: LocalizedError, Equatable {
    case unreachable(String)
    case refused(Int32)
    case timeout
    case rejected(String)

    public var errorDescription: String? {
        switch self {
        case .unreachable(let reason): "amxd is not reachable: \(reason)"
        case .refused(let code): String(cString: strerror(code))
        case .timeout: "amxd did not reply."
        case .rejected(let problem): problem
        }
    }
}

/// App-side XPC client for `amxd`. One connection, recreated after invalidation or interruption.
public final class DaemonClient: @unchecked Sendable {
    private let machServiceName: String
    private let lock = NSLock()
    private var connection: NSXPCConnection?

    public convenience init() { self.init(machServiceName: AMX.daemonLabel) }

    init(machServiceName: String) { self.machServiceName = machServiceName }

    deinit { connection?.invalidate() }

    public func ping() async throws -> DaemonPing {
        let json: String = try await call { proxy, reply in proxy.ping { reply($0) } }
        return try JSONDecoder().decode(DaemonPing.self, from: Data(json.utf8))
    }

    public func settings() async throws -> DaemonSettings {
        let data: Data = try await call { proxy, reply in proxy.settings { reply($0) } }
        return try DaemonSettings.decodeValidated(data)
    }

    public func setSettings(_ s: DaemonSettings) async throws {
        let json = try s.encoded()
        let problem: String? = try await call { proxy, reply in proxy.setSettings(json) { reply($0) } }
        if let problem { throw DaemonClientError.rejected(problem) }
    }

    public func live() async throws -> LiveSnapshot? {
        let data: Data? = try await call { proxy, reply in proxy.live { reply($0) } }
        return try data.map { try JSONDecoder().decode(LiveSnapshot.self, from: $0) }
    }

    /// Processes in batches of `OpenFiles.maxProcesses`; a process that has exited or belongs to another user has no entry.
    public func openFiles(_ ids: [ProcessIdentity]) async throws -> [OpenItems] {
        var out: [OpenItems] = []
        for start in stride(from: 0, to: ids.count, by: OpenFiles.maxProcesses) {
            let request = try JSONEncoder().encode(Array(ids[start..<min(ids.count, start + OpenFiles.maxProcesses)]))
            let data: Data? = try await call { proxy, reply in proxy.openFiles(request) { reply($0) } }
            guard let data else { throw DaemonClientError.rejected("amxd refused the request.") }
            out += try JSONDecoder().decode([OpenItems].self, from: data)
        }
        return out
    }

    public func signal(pid: Int32, startTime: Double, signal: Int32) async throws {
        let result: Int32 = try await call { proxy, reply in
            proxy.signal(pid: pid, startTime: startTime, signal: signal) { reply($0) }
        }
        if result != 0 { throw DaemonClientError.refused(result) }
    }

    private func call<T: Sendable>(_ body: (DaemonXPC, @escaping @Sendable (T) -> Void) -> Void) async throws -> T {
        let c = currentConnection()
        return try await withCheckedThrowingContinuation { continuation in
            let once = Once(continuation, timeout: 3)
            let proxy = c.remoteObjectProxyWithErrorHandler { error in
                once.resume(.failure(DaemonClientError.unreachable(error.localizedDescription)))
            } as! DaemonXPC
            body(proxy) { once.resume(.success($0)) }
        }
    }

    private func currentConnection() -> NSXPCConnection {
        lock.lock()
        defer { lock.unlock() }
        if let connection { return connection }
        let c = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: DaemonXPC.self)
        c.interruptionHandler = { [weak c] in c?.invalidate() }
        c.invalidationHandler = { [weak self, weak c] in self?.drop(c) }
        c.resume()
        connection = c
        return c
    }

    private func drop(_ c: NSXPCConnection?) {
        lock.lock()
        defer { lock.unlock() }
        if connection === c { connection = nil }
    }
}

/// Resumes its continuation once; later calls (error handler, reply, timeout) are ignored.
/// Fails with `timeout` after `timeout` seconds; the first resume cancels that timer.
private final class Once<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var timer: DispatchWorkItem?

    init(_ continuation: CheckedContinuation<T, Error>, timeout: Double) {
        self.continuation = continuation
        let item = DispatchWorkItem { [self] in resume(.failure(DaemonClientError.timeout)) }
        timer = item
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
    }

    func resume(_ result: Result<T, Error>) {
        lock.lock()
        let c = continuation
        continuation = nil
        timer?.cancel()
        timer = nil  // breaks the item's hold on self
        lock.unlock()
        c?.resume(with: result)
    }
}

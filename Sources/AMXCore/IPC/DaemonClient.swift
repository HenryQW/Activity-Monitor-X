import Foundation

public enum DaemonClientError: LocalizedError, Equatable {
    case unreachable(String)
    case refused(Int32)
    case timeout

    public var errorDescription: String? {
        switch self {
        case .unreachable(let reason): "amxd is not reachable: \(reason)"
        case .refused(let code): String(cString: strerror(code))
        case .timeout: "amxd did not reply."
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

    public func live() async throws -> LiveSnapshot? {
        let data: Data? = try await call { proxy, reply in proxy.live { reply($0) } }
        return try data.map { try JSONDecoder().decode(LiveSnapshot.self, from: $0) }
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
            let once = Once(continuation)
            let proxy = c.remoteObjectProxyWithErrorHandler { error in
                once.resume(.failure(DaemonClientError.unreachable(error.localizedDescription)))
            } as! DaemonXPC
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { once.resume(.failure(DaemonClientError.timeout)) }
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
private final class Once<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) { self.continuation = continuation }

    func resume(_ result: Result<T, Error>) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(with: result)
    }
}

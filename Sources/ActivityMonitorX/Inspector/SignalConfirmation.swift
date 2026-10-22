import AMXCore
import AppKit
import Darwin
import SwiftUI

/// A process to signal through amxd, or an app bundle to quit through AppKit: the app can ask to
/// save, and nothing it did not start itself is touched.
struct SignalRequest {
    enum Target {
        case process(ProcessRank)
        /// The app's name and its running copies (one bundle path).
        case app(String, [NSRunningApplication])
    }

    let target: Target
    let signal: Int32

    init(process: ProcessRank, signal: Int32) { (target, self.signal) = (.process(process), signal) }
    init(app name: String, running: [NSRunningApplication], signal: Int32) { (target, self.signal) = (.app(name, running), signal) }

    var verb: String { signal == SIGKILL ? "Force Quit" : "Quit" }
    var title: String {
        switch target {
        case .process(let p): "\(verb) “\(p.name)” (PID \(p.pid))?"
        case .app(let name, _): "\(verb) “\(name)”?"
        }
    }
    var message: String {
        switch (target, signal == SIGKILL) {
        case (.process, true): "The process stops at once. Unsaved changes are lost."
        case (.process, false): "The process is asked to quit."
        case (.app, true): "The app stops at once. Unsaved changes are lost."
        case (.app, false): "The app is asked to quit. It can ask to save changes first."
        }
    }
}

/// Confirms `Selection.signalRequest` (from the inspector or the Process menu), sends it through amxd or AppKit,
/// and shows the failure.
struct SignalConfirmation: ViewModifier {
    @Environment(Selection.self) private var selection
    @Environment(LiveModel.self) private var live
    @Environment(HistoryModel.self) private var history
    private let _failure = State<Failure?>(initialValue: nil)

    func body(content: Content) -> some View {
        let failure = _failure.wrappedValue
        content
            .confirmationDialog(selection.signalRequest?.title ?? "",
                                isPresented: Binding(get: { selection.signalRequest != nil },
                                                     set: { if !$0 { selection.signalRequest = nil } }),
                                titleVisibility: .visible, presenting: selection.signalRequest) { request in
                Button(request.verb, role: .destructive) { send(request) }
                Button("Cancel", role: .cancel) {}
            } message: { request in
                Text(request.message)
            }
            .alert(failure?.title ?? "",
                   isPresented: Binding(get: { failure != nil }, set: { if !$0 { _failure.wrappedValue = nil } }),
                   presenting: failure) { _ in
                Button("OK") {}
            } message: { failure in
                Text(failure.message)
            }
    }

    private func send(_ request: SignalRequest) {
        if case .app(let name, let running) = request.target {
            // terminate() is false only when the request cannot be sent; the app may still decline to quit.
            if !running.map({ request.signal == SIGKILL ? $0.forceTerminate() : $0.terminate() }).allSatisfy({ $0 }) {
                _failure.wrappedValue = Failure(title: "Cannot \(request.verb) “\(name)”", message: "The app did not accept the request.")
            }
            return
        }
        guard case .process(let process) = request.target else { return }
        Task {
            do {
                try await live.client.signal(pid: process.pid, startTime: process.startTime, signal: request.signal)
                // The process ends: drop it from the selection and show the change at once.
                if let current = selection.process, current.pid == process.pid, current.startTime == process.startTime {
                    selection.process = nil
                }
                if history.range == .live { await live.refresh() } else { history.reload() }
            } catch {
                _failure.wrappedValue = Failure(title: "Cannot \(request.verb) “\(process.name)”", message: Self.message(error))
            }
        }
    }

    private static func message(_ error: Error) -> String {
        error as? DaemonClientError == .refused(ESRCH) ? "Process has already exited." : error.localizedDescription
    }

    private struct Failure {
        let title: String
        let message: String
    }
}

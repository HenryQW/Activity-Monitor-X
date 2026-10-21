import AMXCore
import Darwin
import SwiftUI

struct SignalRequest {
    let process: ProcessRank
    let signal: Int32

    var verb: String { signal == SIGKILL ? "Force Quit" : "Quit" }
    var title: String { "\(verb) “\(process.name)” (PID \(process.pid))?" }
}

/// Confirms `Selection.signalRequest` (from the inspector or the Process menu), sends it through amxd,
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
                Text(request.signal == SIGKILL ? "The process stops at once. Unsaved changes are lost." : "The process is asked to quit.")
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
        Task {
            do {
                try await live.client.signal(pid: request.process.pid, startTime: request.process.startTime,
                                             signal: request.signal)
                // The process ends: drop it from the selection and show the change at once.
                if let current = selection.process, current.pid == request.process.pid,
                   current.startTime == request.process.startTime {
                    selection.process = nil
                }
                if history.range == .live { await live.refresh() } else { history.reload() }
            } catch {
                _failure.wrappedValue = Failure(title: "Cannot \(request.verb) “\(request.process.name)”",
                                                message: Self.message(error))
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

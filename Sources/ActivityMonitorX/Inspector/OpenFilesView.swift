import AMXCore
import AppKit
import SwiftUI

/// The open files and sockets of an app's running processes, read from `amxd` when the Files pill shows and on
/// Refresh; no polling.
@Observable @MainActor
final class OpenFilesModel {
    /// The processes of the last load, and what `amxd` gave for each by pid.
    private(set) var processes: [ProcessRank] = []
    private(set) var found: [Int32: OpenItems] = [:]
    private(set) var error: String?
    private(set) var loading = false

    func load(_ processes: [ProcessRank], client: DaemonClient) async {
        loading = true
        defer { loading = false }
        do {
            // Version 5 adds `openFiles`; an older helper would not reply.
            guard try await client.ping().version >= 5 else {
                throw DaemonClientError.rejected("The helper is out of date. Update it to see open files. See Helper in Settings.")
            }
            let items = try await client.openFiles(processes.map { ProcessIdentity(pid: $0.pid, startTime: $0.startTime) })
            found = Dictionary(items.map { ($0.pid, $0) }, uniquingKeysWith: { $1 })
            self.processes = processes
            error = nil
        } catch {
            self.processes = []
            found = [:]
            self.error = error.localizedDescription
        }
    }
}

/// The Files pill's sections in a grouped Form: the state with Refresh, then a section per process.
struct OpenFilesRows: View {
    let model: OpenFilesModel
    let processes: [ProcessRank]
    let client: DaemonClient

    var body: some View {
        Section {
            LabeledContent {
                HStack {
                    if model.loading { ProgressView().controlSize(.small) }
                    Button("Refresh") { Task { await model.load(processes, client: client) } }
                        .disabled(model.loading)
                        .help("Read the open files and network connections again")
                }
            } label: {
                Text(model.error ?? (processes.isEmpty ? "No running processes" : "Open files and network connections"))
            }
        }
        ForEach(model.processes, id: \.pid) { p in
            Section("\(p.name) (\(String(p.pid)))") {
                if let open = model.found[p.pid] {
                    if open.items.isEmpty { Text("No open files").foregroundStyle(.secondary) }
                    ForEach(open.items, id: \.self) { ItemRow(item: $0) }
                    if open.more > 0 { Text("\(open.more.formatted()) more").foregroundStyle(.secondary) }
                } else {
                    Text("Not available: the process has quit or runs as another user").foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A file's path, or a socket's addresses with its protocol and state below.
private struct ItemRow: View {
    let item: OpenItem

    var body: some View {
        switch item {
        case .file(let path):
            Text(path).lineLimit(1).truncationMode(.middle).help(path)
                .contextMenu {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)]) }
                    Button("Copy Path") { copy(path) }
                }
        case .socket(let proto, let local, let remote, let state):
            let text = remote.isEmpty || remote == "*" ? local : "\(local) → \(remote)"
            VStack(alignment: .leading) {
                Text(text).lineLimit(1).truncationMode(.middle)
                Text([proto, state].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
            .help(text)
            .contextMenu { Button("Copy") { copy(text) } }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

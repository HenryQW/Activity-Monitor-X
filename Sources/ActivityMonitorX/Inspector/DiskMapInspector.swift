import AMXCore
import SwiftUI

/// The Disk Map item selected in the table, or else the shown folder: its size, kind, modified date and path, with
/// Show in Finder; the shown folder also lists its largest items, and at the top the folders the scan could not read.
struct DiskMapInspector: View {
    @Environment(DiskMapModel.self) private var model

    var body: some View {
        if let tree = model.tree, !model.isScanning {
            let indexPath = model.selected ?? model.focus
            let node = tree[indexPath]
            let path = model.path(indexPath)
            Form {
                Section { Text(indexPath.isEmpty ? model.title : node.name).font(.title3.bold()) }
                Section(model.selected == nil ? "Shown Folder" : "Item") {
                    LabeledContent("Kind", value: Self.kind(node.kind))
                    LabeledContent("Size", value: node.kind == .refused ? "Not readable" : Metric.bytes(Double(node.size)))
                    LabeledContent("Items", value: node.items.formatted())
                    if model.selected == nil && indexPath.isEmpty && tree.refusedCount > 0 {
                        LabeledContent("Not readable", value: "\(tree.refusedCount.formatted()) folders")
                    }
                    if let modified = path.flatMap(Self.modified) {
                        LabeledContent("Modified", value: modified.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                .monospacedDigit()
                // With no item selected, the shown folder's largest items; a click selects one.
                if model.selected == nil {
                    let largest = node.children.indices.filter { [.folder, .file].contains(node.children[$0].kind) }.prefix(5)
                    if !largest.isEmpty {
                        Section {
                            ForEach(largest, id: \.self) { i in
                                Button { model.selected = indexPath + [i] } label: {
                                    LabeledContent(node.children[i].name, value: Metric.bytes(Double(node.children[i].size)))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("Select \(node.children[i].name)")
                            }
                        } header: {
                            Text("Largest Items")
                        } footer: {
                            Text("Click an item to see its details.")
                        }
                        .monospacedDigit()
                    }
                }
                if let path {
                    Section("Path") {
                        Text(path).textSelection(.enabled)
                        HStack { DiskItemMenu(path: path) }
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("No Selection", systemImage: "square.grid.3x3.square",
                                   description: Text("Scan a volume or folder, then click an item."))
        }
    }

    private static func kind(_ kind: DiskTree.Node.Kind) -> String {
        switch kind {
        case .folder: "Folder"
        case .file: "File"
        case .smaller: "Small items, grouped"
        case .refused: "Folder, not readable"
        }
    }

    private static func modified(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}

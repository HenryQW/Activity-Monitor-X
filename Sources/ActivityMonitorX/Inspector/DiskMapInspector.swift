import AMXCore
import AppKit
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
                // The shown root needs no title row: the title pill's subtitle names it.
                if !indexPath.isEmpty { InspectorTitle(node.name) }
                CardSection(model.selected == nil ? "Shown Folder" : "Item",
                            summary: Text(node.kind == .refused ? "Not readable" : Metric.bytes(Double(node.size)))) {
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
                        CardSection("Largest Items", summary: largest.first.map { Text(node.children[$0].name) },
                                    footer: Text("Click an item to see its details.")) {
                            ForEach(largest, id: \.self) { i in
                                Button { model.selected = indexPath + [i] } label: {
                                    LabeledContent(node.children[i].name, value: Metric.bytes(Double(node.children[i].size)))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("Select \(node.children[i].name)")
                            }
                        }
                        .monospacedDigit()
                    }
                }
                if let path {
                    CardSection("Path", summary: Text(((path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath)) {
                        Text(path).textSelection(.enabled)
                        HStack {
                            ShowInFinderButton(path: path, help: "Show the item in Finder").labelStyle(.titleOnly)
                            Button("Copy Path") { Pasteboard.copy(path) }
                                .help("Copy the path of the item")
                        }
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("No Selection", systemImage: "square.grid.3x3.square",
                                   description: Text("Choose a volume or folder, then click an item."))
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

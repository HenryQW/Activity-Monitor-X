import AMXCore
import AppKit
import SwiftUI

extension ProcessGroup {
    /// What New Group… opens: one empty condition, so the first edit is typing a value.
    static var new: ProcessGroup { ProcessGroup(name: "", rule: .any([.condition(.empty)])) }
}

/// The sheet for `Selection.editingGroup`: name, symbol, colour, rule, and the recent processes the rule matches (M3-D16).
struct GroupEditor: View {
    private static let symbols: KeyValuePairs = ["folder": "Folder", "hammer": "Hammer", "terminal": "Terminal",
                                                 "globe": "Globe", "shield": "Shield", "lock": "Lock", "briefcase": "Briefcase",
                                                 "cloud": "Cloud", "cpu": "CPU", "bolt": "Bolt",
                                                 "gamecontroller": "Game Controller", "star": "Star"]
    /// Menus draw SwiftUI images as templates; a palette-coloured symbol keeps its colour.
    static let swatches = Dictionary(uniqueKeysWithValues: GroupColor.allCases.map { color in
        let symbol = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)!
        return (color, symbol.withSymbolConfiguration(.init(paletteColors: [NSColor(color.color)]))!)
    })
    private static let rowLimit = 200

    private let _draft: State<ProcessGroup>
    /// Nil until loaded on appear.
    private let _processes = State<[ProcessTrack]?>(initialValue: nil)
    private let _loadError = State<String?>(initialValue: nil)
    private let _saveError = State<String?>(initialValue: nil)
    @Environment(GroupsModel.self) private var groups
    @Environment(\.dismiss) private var dismiss

    init(group: ProcessGroup) {
        var group = group
        // A root condition (hand-edited or from amx) becomes a group the editor can add to; it matches the same processes.
        if group.rule.kind == nil { group.rule = group.rule.with(kind: .any) }
        _draft = State(initialValue: group)
    }

    var body: some View {
        let draft = _draft.projectedValue
        let problem = draft.wrappedValue.validationProblem(among: groups.groups)
        let matches = GroupScores.members(_processes.wrappedValue ?? [], of: draft.wrappedValue)
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: draft.name)
                    Picker("Symbol", selection: draft.symbol) {
                        // A symbol set outside the editor (amx, a hand edit) stays selectable, so the picker is never blank.
                        let stored = draft.wrappedValue.symbol
                        ForEach(Self.symbols.contains { $0.key == stored } ? [] : [stored], id: \.self) {
                            Label($0, systemImage: $0).tag($0)
                        }
                        ForEach(Self.symbols, id: \.key) { Label($0.value, systemImage: $0.key).tag($0.key) }
                    }
                    Picker("Colour", selection: draft.color) {
                        ForEach(GroupColor.allCases, id: \.self) { color in
                            Label { Text(color.rawValue.capitalized) } icon: { Image(nsImage: Self.swatches[color]!) }.tag(color)
                        }
                    }
                }
                Section("Rule") {
                    RuleEditor(rule: draft.rule)
                }
                Section("Matching Processes (\(matches.count))") {
                    if let error = _loadError.wrappedValue {
                        Text("History unavailable: \(error)").foregroundStyle(.secondary)
                    } else if _processes.wrappedValue == nil {
                        ProgressView().controlSize(.small)
                    } else if matches.isEmpty {
                        Text("No process seen in the last minute matches.").foregroundStyle(.secondary)
                    }
                    ForEach(matches.prefix(Self.rowLimit), id: \.processID) { track in
                        HStack {
                            Text(track.name)
                            Spacer()
                            Text(track.app.name).foregroundStyle(.secondary)
                            Text(String(track.pid)).monospacedDigit().foregroundStyle(.secondary)
                                .frame(minWidth: 56, alignment: .trailing)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                if let problem { Text(problem).foregroundStyle(.secondary) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save(draft.wrappedValue) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
            }
            .padding()
        }
        .frame(width: 560, height: 640)
        .task {
            do {
                _processes.wrappedValue = try await groups.recentProcesses()
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            } catch {
                _loadError.wrappedValue = error.localizedDescription
            }
        }
        .alert("Cannot Save Group",
               isPresented: Binding(get: { _saveError.wrappedValue != nil }, set: { if !$0 { _saveError.wrappedValue = nil } }),
               presenting: _saveError.wrappedValue) { _ in } message: { Text($0) }
    }

    private func save(_ draft: ProcessGroup) {
        var group = draft
        group.name = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try groups.save(group)
            dismiss()
        } catch {
            _saveError.wrappedValue = error.localizedDescription
        }
    }
}

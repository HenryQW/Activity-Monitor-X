import AMXCore
import SwiftUI

/// One rule node as Form rows: a group row with its kind, its children indented below,
/// then the add buttons; a condition row with field, operator, value and a remove button.
struct RuleEditor: View {
    let rule: Binding<GroupRule>
    var depth = 0
    /// Nil for the root and for the one child of a Not, which cannot be removed.
    var remove: (() -> Void)?

    var body: some View {
        if case .condition(let condition) = rule.wrappedValue {
            conditionRow(condition)
        } else {
            groupRows
        }
    }

    @ViewBuilder private var groupRows: some View {
        let kind = rule.wrappedValue.kind ?? .any
        HStack {
            Picker("Match", selection: Binding(get: { kind }, set: { rule.wrappedValue = rule.wrappedValue.with(kind: $0) })) {
                ForEach(GroupRule.Kind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            Text(kind == .not ? "the following is true" : "of the following are true")
            Spacer()
            removeButton
        }
        .padding(.leading, indent)
        // Index bindings: a row being removed can still read its old index once.
        ForEach(rule.wrappedValue.children.indices, id: \.self) { i in
            RuleEditor(rule: Binding(get: { rule.wrappedValue.children.indices.contains(i) ? rule.wrappedValue.children[i] : .any([]) },
                                     set: { if rule.wrappedValue.children.indices.contains(i) { rule.wrappedValue.children[i] = $0 } }),
                       depth: depth + 1,
                       remove: kind == .not ? nil : {
                           if rule.wrappedValue.children.indices.contains(i) { rule.wrappedValue.children.remove(at: i) }
                       })
        }
        if kind != .not {
            HStack {
                Button("Add Condition") { rule.wrappedValue.children.append(.condition(.empty)) }
                Button("Add Group") { rule.wrappedValue.children.append(.all([.condition(.empty)])) }
            }
            .padding(.leading, indent + 20)
        }
    }

    private func conditionRow(_ condition: GroupCondition) -> some View {
        let c = Binding(get: { if case .condition(let now) = rule.wrappedValue { now } else { condition } },
                        set: { rule.wrappedValue = .condition($0) })
        return HStack {
            Picker("Field", selection: c.field) {
                ForEach(GroupCondition.Field.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            Picker("Operator", selection: c.op) {
                ForEach(GroupCondition.Op.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            TextField("Value", text: c.value, prompt: Text("Value"))
                .labelsHidden()
            removeButton
        }
        .padding(.leading, indent)
    }

    @ViewBuilder private var removeButton: some View {
        if let remove {
            Button(action: remove) { Label(rule.wrappedValue.kind == nil ? "Remove Condition" : "Remove Group",
                                           systemImage: "minus.circle").labelStyle(.iconOnly) }
                .buttonStyle(.borderless)
                .help(rule.wrappedValue.kind == nil ? "Remove this condition" : "Remove this group")
        }
    }

    private var indent: CGFloat { CGFloat(depth) * 20 }
}

extension GroupCondition {
    static var empty: GroupCondition { GroupCondition(field: .name, op: .contains, value: "") }
}

private extension GroupCondition.Field {
    var label: String {
        switch self {
        case .name: "Name"
        case .bundleID: "Bundle ID"
        case .path: "Path"
        case .teamID: "Team ID"
        }
    }
}

private extension GroupCondition.Op {
    var label: String {
        switch self {
        case .equals: "is"
        case .contains: "contains"
        case .startsWith: "starts with"
        }
    }
}

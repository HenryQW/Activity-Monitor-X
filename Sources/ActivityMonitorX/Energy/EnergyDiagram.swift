import AMXCore
import SwiftUI

/// The live energy flow: the adapter and the battery into the Mac, the Mac into its top apps and Other, each band as wide
/// as its watts (`SankeyLayout`). Sources, the Mac and the battery are in the accent colour, apps and their processes in
/// the app's chart colour. A click on an app's band or label selects the app and opens it into its processes, or folds
/// it; a click on a process selects it. A right-click on an app or a process opens its actions.
struct EnergyDiagram: View {
    let power: PowerReading
    let flows: EnergyFlows
    let colors: [AppKey: Color]
    let model: EnergyModel
    @Environment(Selection.self) private var selection
    @Environment(HistoryModel.self) private var history
    @Environment(LiveModel.self) private var live
    /// The app or process under the pointer, and the pointer's place in the diagram.
    private let _hover = State<(node: EnergyNode, point: CGPoint)?>(initialValue: nil)

    private static let nodeWidth = 10.0, gap = 14.0, leading = 150.0, trailing = 210.0, top = 22.0, bottom = 22.0

    private struct Change: Equatable {
        let expanded: AppKey?
        let kept: Set<String>
        let byName: Bool
    }

    var body: some View {
        GeometryReader { proxy in
            let size = CGSize(width: max(0, proxy.size.width - Self.leading - Self.trailing),
                              height: max(0, proxy.size.height - Self.top - Self.bottom))
            let nodes = flows.columns.flatMap { $0 }
            let column = flows.columns.enumerated().flatMap { c, nodes in nodes.map { _ in c } }
            let index = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1, $0) })
            let placed = SankeyLayout.layout(columns: column, links: flows.links.map { (index[$0.from]!, index[$0.to]!, $0.weight) },
                                             size: size, nodeWidth: Self.nodeWidth, gap: Self.gap)
            ZStack(alignment: .topLeading) {
                ForEach(Array(zip(flows.links, placed.bands)), id: \.0.id) { link, band in
                    let app = owner(link.to)
                    BandShape(x0: band.x0, y0: band.y0, x1: band.x1, y1: band.y1, thickness: band.thickness)
                        .fill([.other, .otherProcesses].contains(link.to) ? AppPalette.other
                              : color(link.from == .mac ? link.to : link.from).opacity(app != nil && app == selection.app ? 0.8 : 0.5))
                        .onTapGesture { click(link.to) }
                        .onContinuousHover(coordinateSpace: .named(Self.space)) { hover(link.to, $0) }
                        .contextMenu { menu(link.to).labelStyle(.titleAndIcon) }
                        .accessibilityElement()
                        .accessibilityLabel("\(spoken(link.from)) to \(spoken(link.to)), \(value(link))")
                        .accessibilityAddTraits(app == nil ? [] : app == selection.app ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { click(link.to) }
                }
                // A node's identity is the node, not its place in the list, so a rectangle never slides to another node.
                ForEach(Array(nodes.enumerated()), id: \.element) { i, _ in
                    let rect = placed.nodes[i]
                    Rectangle()
                        .fill(color(nodes[i]))
                        .frame(width: rect.width, height: max(1, rect.height))
                        .position(x: rect.midX, y: rect.midY)
                        .accessibilityElement()
                        .accessibilityLabel("\(spoken(nodes[i])), \(value(nodes[i]))")
                }
                labels(nodes: nodes, column: column, rects: placed.nodes, size: size)
                    .accessibilityHidden(true)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .coordinateSpace(.named(Self.space))
            .previewBeside(_hover.wrappedValue?.point) {
                if let node = _hover.wrappedValue?.node { card(node) }
            }
            .offset(x: Self.leading, y: Self.top)
        }
        // The bands move for a change the user made (open or fold an app, keep, sort), never for a Live tick.
        .animation(Motion.smooth(0.3), value: Change(expanded: model.expanded, kept: model.kept, byName: model.sortsByName))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(summary)
    }

    /// Each end is the thing it is: the adapter's symbol and the battery as Hardware draws it (SCR-19) left of their nodes,
    /// the Mac's symbol above its node and a charging battery below its node, each app's icon on the right (processes and
    /// Other, a group, keep the icon column empty); app labels are as wide as the space to the process column.
    @ViewBuilder private func labels(nodes: [EnergyNode], column: [Int], rects: [CGRect], size: CGSize) -> some View {
        let sources = nodes.indices.filter { column[$0] == 0 }
        let last = flows.columns.count - 1
        let step = (size.width - Self.nodeWidth) / Double(last)
        let sourceY = SankeyLayout.spread(sources.map { rects[$0].midY }, spacing: 40, in: 20...max(20, size.height - 20))
        ForEach(Array(sources.enumerated()), id: \.element) { k, i in
            HStack(spacing: 6) {
                Text(value(nodes[i])).fontWeight(.semibold).monospacedDigit()
                icon(nodes[i]).frame(width: 30)
            }
            .lineLimit(1)
            .help(name(nodes[i]))
            .frame(width: Self.leading - 8, alignment: .trailing)
            .position(x: rects[i].minX - Self.leading / 2 - 4, y: sourceY[k])
        }
        ForEach(Array(nodes.enumerated()).filter { column[$0.offset] == 1 }, id: \.element) { i, _ in
            HStack(spacing: 6) {
                icon(nodes[i])
                Text(value(nodes[i])).fontWeight(.semibold).monospacedDigit()
            }
            .lineLimit(1)
            .fixedSize()
            .help(name(nodes[i]))
            .position(x: rects[i].midX, y: nodes[i] == .mac ? rects[i].minY - 11 : rects[i].maxY + 11)
        }
        ForEach(2...max(2, last), id: \.self) { c in
            let members = nodes.indices.filter { column[$0] == c }.map { (index: $0, node: nodes[$0]) }
            let y = SankeyLayout.spread(members.map { rects[$0.index].midY }, spacing: 18, in: 9...max(9, size.height - 9))
            let width = max(0, c == last ? Self.trailing - 8 : step - Self.nodeWidth - 8)
            ForEach(Array(members.enumerated()), id: \.element.node) { k, member in
                let i = member.index
                let app: AppKey? = if case .app(let app) = nodes[i] { app } else { nil }
                HStack(spacing: 6) {
                    icon(nodes[i]).frame(width: 16)
                    Text(name(nodes[i])).truncationMode(.middle).fontWeight(app != nil && app == selection.app ? .semibold : nil)
                    Text(value(nodes[i])).foregroundStyle(.secondary).monospacedDigit().layoutPriority(1)
                }
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { click(nodes[i]) }
                .onContinuousHover(coordinateSpace: .named(Self.space)) { hover(nodes[i], $0) }
                .contextMenu { menu(nodes[i]).labelStyle(.titleAndIcon) }
                .position(x: rects[i].maxX + width / 2 + 4, y: y[k])
            }
        }
    }

    private static let space = "energy"

    /// The thing a node is: the adapter's and the Mac's symbols, the drawn battery, an app's icon; nothing for a process
    /// or Other.
    @ViewBuilder private func icon(_ node: EnergyNode) -> some View {
        switch node {
        case .adapter: Image(systemName: "powerplug.portrait").imageScale(.large).foregroundStyle(.secondary)
        case .battery:
            let battery = power.battery
            BatteryShape(percent: battery?.percent.map(Double.init), charging: battery?.charging == true,
                         level: BatteryShape.level(percent: battery?.percent, charging: battery?.charging == true))
        case .mac: Image(systemName: power.battery == nil ? "desktopcomputer" : "laptopcomputer").imageScale(.large).foregroundStyle(.secondary)
        case .app(let app): Image(nsImage: AppIcon.image(for: app)).resizable().frame(width: 16, height: 16)
        case .process, .other, .otherProcesses: EmptyView()
        }
    }

    /// Set once per node, where the pointer entered: a rebuild per mouse move is not needed.
    private func hover(_ node: EnergyNode, _ phase: HoverPhase) {
        switch phase {
        case .active(let point): if _hover.wrappedValue?.node != node { _hover.wrappedValue = (node, point) }
        case .ended: if _hover.wrappedValue?.node == node { _hover.wrappedValue = nil }
        }
    }

    /// An app, a process or Other: its watts now and its share of the Mac, or of the app for a process. The same words as
    /// the band's accessibility label.
    private func card(_ node: EnergyNode) -> some View {
        let link = flows.links.first { $0.to == node }
        let total = flows.links.filter { $0.from == link?.from }.reduce(0) { $0 + $1.weight }
        let share = link.map { (total > 0 ? $0.weight / total : 0).formatted(.percent.precision(.fractionLength(0))) }
        return PreviewCard(size: .compact, title: name(node), top: link?.watts.map { Self.watts($0) },
                           sections: [.init(rows: share.map { [.init(label: link?.from == .mac ? "Share of the Mac" : "Share of \(name(link!.from))", value: $0)] } ?? [])])
    }

    /// The app a node belongs to: an app, or the expanded app of a process.
    private func owner(_ node: EnergyNode) -> AppKey? {
        switch node {
        case .app(let app): app
        case .process, .otherProcesses: model.expanded
        case .adapter, .battery, .mac, .other: nil
        }
    }

    /// Selects the node's app; an app also opens into its processes or folds, and a process is selected too.
    private func click(_ node: EnergyNode) {
        guard let app = owner(node) else { return }
        selection.app = app
        switch node {
        case .app: model.expanded = model.expanded == app ? nil : app
        case .process(let pid, let startTime, _):
            let rank = history.range == .live ? live.rank(of: app) : history.rank(of: app)
            selection.process = rank?.processes.first { $0.pid == pid && $0.startTime == startTime }
        default: break
        }
    }

    /// The right-click actions of an app or a process.
    @ViewBuilder private func menu(_ node: EnergyNode) -> some View {
        if let app = owner(node), node != .otherProcesses {
            Button("Show in Inspector", systemImage: "sidebar.trailing") {
                if case .process = node { click(node) } else { selection.app = app }
                selection.inspectorShown = true
            }
            .help("Show \(name(node)) in the inspector")
        }
        if case .app(let app) = node {
            Button("Show in Apps", systemImage: "app.badge") {
                selection.app = app
                history.metric = .energy
                history.range = .live
                selection.showChart = true
                selection.sidebar = .apps
            }
            .help("Show the live energy of \(app.name) in Apps")
            let kept = model.kept.contains(app.key)
            Button(kept ? "Remove from Flow" : "Keep in Flow", systemImage: kept ? "minus.circle" : "plus.circle") {
                if kept { model.kept.remove(app.key) } else { model.kept.insert(app.key) }
            }
            .help(kept ? "Show \(app.name) only while it is in the top 5" : "Always show \(app.name) in the flow while it runs")
            let pinned = selection.isPinned(app)
            Button(pinned ? "Unpin from Sidebar" : "Pin to Sidebar", systemImage: pinned ? "pin.slash" : "pin") { selection.togglePin(app) }
                .help(pinned ? "Unpin \(app.name)" : "Pin \(app.name) to the sidebar")
            Menu("Colour", systemImage: "paintpalette") { AppColorPicker(app: app, history: history) }
                .help("Choose the colour that shows \(app.name)")
        }
    }

    private func color(_ node: EnergyNode) -> Color {
        switch node {
        case .app(let app): colors[app] ?? AppPalette.other
        case .process: model.expanded.flatMap { colors[$0] } ?? AppPalette.other
        case .other, .otherProcesses: AppPalette.other
        case .adapter, .battery, .mac: .accentColor
        }
    }

    private func name(_ node: EnergyNode) -> String {
        switch node {
        case .adapter: "Adapter"
        case .battery: "Battery"
        case .mac: "Mac"
        case .app(let app): app.name
        case .process(_, _, let name): name
        case .other, .otherProcesses: "Other"
        }
    }

    /// The name for VoiceOver: a process has its PID too.
    private func spoken(_ node: EnergyNode) -> String {
        if case .process(let pid, _, let name) = node { "\(name), PID \(pid)" } else { name(node) }
    }

    private func value(_ node: EnergyNode) -> String {
        switch node {
        case .adapter:
            let rating = power.adapterRating.map { " of \(Self.watts($0, digits: 0))" } ?? ""
            return power.adapterWatts.map { Self.watts($0) + rating } ?? "Not available"
        case .battery:
            let watts = power.battery?.watts.map { $0 > 0 ? "\(Self.watts($0)) in" : $0 < 0 ? "\(Self.watts(-$0)) out" : Self.watts(0) }
            let percent = power.battery?.percent.map { (Double($0) / 100).formatted(.percent) }
            return [watts ?? "Not available", percent].compactMap { $0 }.joined(separator: ", ")
        case .mac: return power.systemWatts.map { Self.watts($0) } ?? "Not available"
        case .app, .other, .process, .otherProcesses: return flows.links.first { $0.to == node }.map(value) ?? "Not available"
        }
    }

    /// A band into an app or a process shows its share too: of the Mac, or of the app.
    private func value(_ link: EnergyFlows.Link) -> String {
        guard link.from != .adapter, link.from != .battery else { return link.watts.map { Self.watts($0) } ?? "Not available" }
        let total = flows.links.filter { $0.from == link.from }.reduce(0) { $0 + $1.weight }
        let share = (total > 0 ? link.weight / total : 0).formatted(.percent.precision(.fractionLength(0)))
        return link.watts.map { "\(Self.watts($0)), \(share)" } ?? share
    }

    private var summary: String {
        let apps = flows.columns[2].prefix(3).map { "\(name($0)) \(value($0))" }
        return (["Energy flow. Mac \(value(.mac))"] + flows.columns[0].map { "\(name($0)) \(value($0))" } + apps)
            .joined(separator: "; ")
    }

    static func watts(_ value: Double, digits: Int = 1) -> String {
        Measurement(value: value, unit: UnitPower.watts)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(digits))))
    }
}

extension EnergyFlows.Link {
    fileprivate var id: [EnergyNode] { [from, to] }
}

/// One band: cubic curves from the source's edge to the target's edge, filled between its top and bottom.
private struct BandShape: Shape {
    var x0, y0, x1, y1, thickness: Double

    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, AnimatablePair<Double, Double>>> {
        get { .init(.init(x0, y0), .init(x1, .init(y1, thickness))) }
        set { (x0, y0, x1, y1, thickness) = (newValue.first.first, newValue.first.second, newValue.second.first,
                                             newValue.second.second.first, newValue.second.second.second) }
    }

    func path(in rect: CGRect) -> Path {
        let mid = (x0 + x1) / 2
        var path = Path()
        path.move(to: CGPoint(x: x0, y: y0))
        path.addCurve(to: CGPoint(x: x1, y: y1), control1: CGPoint(x: mid, y: y0), control2: CGPoint(x: mid, y: y1))
        path.addLine(to: CGPoint(x: x1, y: y1 + thickness))
        path.addCurve(to: CGPoint(x: x0, y: y0 + thickness), control1: CGPoint(x: mid, y: y1 + thickness),
                      control2: CGPoint(x: mid, y: y0 + thickness))
        path.closeSubpath()
        return path
    }
}

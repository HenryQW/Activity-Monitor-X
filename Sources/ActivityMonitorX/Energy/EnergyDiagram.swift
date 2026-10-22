import AMXCore
import SwiftUI

/// The live energy flow: the adapter and the battery into the Mac, the Mac into its top apps and Other, each band as wide
/// as its watts (`SankeyLayout`). Sources, the Mac and the battery are in the accent colour, apps in their chart colour.
/// A click on an app's band or label selects the app.
struct EnergyDiagram: View {
    let power: PowerReading
    let flows: EnergyFlows
    let colors: [AppKey: Color]
    let selected: AppKey?
    let select: (AppKey) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let nodeWidth = 10.0, gap = 14.0, leading = 150.0, trailing = 210.0, top = 22.0, bottom = 22.0

    private struct LinkID: Hashable {
        let from, to: EnergyNode
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
                    let app: AppKey? = if case .app(let app) = link.to { app } else { nil }
                    BandShape(x0: band.x0, y0: band.y0, x1: band.x1, y1: band.y1, thickness: band.thickness)
                        .fill(link.to == .other ? AppPalette.other
                              : color(link.from == .mac ? link.to : link.from).opacity(app != nil && app == selected ? 0.8 : 0.5))
                        .onTapGesture { app.map(select) }
                        .accessibilityElement()
                        .accessibilityLabel("\(name(link.from)) to \(name(link.to)), \(value(link))")
                        .accessibilityAddTraits(app == nil ? [] : app == selected ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { app.map(select) }
                }
                ForEach(nodes.indices, id: \.self) { i in
                    let rect = placed.nodes[i]
                    Rectangle()
                        .fill(color(nodes[i]))
                        .frame(width: rect.width, height: max(1, rect.height))
                        .position(x: rect.midX, y: rect.midY)
                        .accessibilityElement()
                        .accessibilityLabel("\(name(nodes[i])), \(value(nodes[i]))")
                }
                labels(nodes: nodes, column: column, rects: placed.nodes, size: size)
                    .accessibilityHidden(true)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .offset(x: Self.leading, y: Self.top)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: flows)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(summary)
    }

    /// Sources on the left of their nodes, the Mac above its node and a charging battery below its node, apps on the right.
    @ViewBuilder private func labels(nodes: [EnergyNode], column: [Int], rects: [CGRect], size: CGSize) -> some View {
        let sources = nodes.indices.filter { column[$0] == 0 }
        let apps = nodes.indices.filter { column[$0] == 2 }
        let sourceY = SankeyLayout.spread(sources.map { rects[$0].midY }, spacing: 40, in: 20...max(20, size.height - 20))
        let appY = SankeyLayout.spread(apps.map { rects[$0].midY }, spacing: 18, in: 9...max(9, size.height - 9))
        ForEach(Array(sources.enumerated()), id: \.element) { k, i in
            VStack(alignment: .trailing, spacing: 1) {
                Text(name(nodes[i])).fontWeight(.semibold)
                Text(value(nodes[i])).foregroundStyle(.secondary).monospacedDigit()
            }
            .lineLimit(1)
            .frame(width: Self.leading - 8, alignment: .trailing)
            .position(x: rects[i].minX - Self.leading / 2 - 4, y: sourceY[k])
        }
        ForEach(nodes.indices.filter { column[$0] == 1 }, id: \.self) { i in
            HStack(spacing: 6) {
                Text(name(nodes[i])).fontWeight(.semibold)
                Text(value(nodes[i])).foregroundStyle(.secondary).monospacedDigit()
            }
            .lineLimit(1)
            .fixedSize()
            .position(x: rects[i].midX, y: nodes[i] == .mac ? rects[i].minY - 11 : rects[i].maxY + 11)
        }
        ForEach(Array(apps.enumerated()), id: \.element) { k, i in
            let app: AppKey? = if case .app(let app) = nodes[i] { app } else { nil }
            HStack(spacing: 6) {
                Text(name(nodes[i])).truncationMode(.middle).fontWeight(app != nil && app == selected ? .semibold : nil)
                Text(value(nodes[i])).foregroundStyle(.secondary).monospacedDigit().layoutPriority(1)
            }
            .lineLimit(1)
            .frame(width: Self.trailing - 8, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { app.map(select) }
            .position(x: rects[i].maxX + Self.trailing / 2 + 4, y: appY[k])
        }
    }

    private func color(_ node: EnergyNode) -> Color {
        switch node {
        case .app(let app): colors[app] ?? AppPalette.other
        case .other: AppPalette.other
        case .adapter, .battery, .mac: .accentColor
        }
    }

    private func name(_ node: EnergyNode) -> String {
        switch node {
        case .adapter: "Adapter"
        case .battery: "Battery"
        case .mac: "Mac"
        case .app(let app): app.name
        case .other: "Other"
        }
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
        case .app, .other: return flows.links.first { $0.to == node }.map(value) ?? "Not available"
        }
    }

    /// A band into an app shows its share too.
    private func value(_ link: EnergyFlows.Link) -> String {
        guard link.from == .mac else { return link.watts.map { Self.watts($0) } ?? "Not available" }
        let total = flows.links.filter { $0.from == .mac }.reduce(0) { $0 + $1.weight }
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

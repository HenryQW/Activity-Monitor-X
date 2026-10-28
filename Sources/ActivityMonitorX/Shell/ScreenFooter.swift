import SwiftUI

/// One figure of a screen's footer: the value over its label, with an optional warning (1) or critical (2) symbol.
struct FooterFigure: Identifiable {
    var id: String { label }
    let label: String
    let value: String
    let help: String
    var severity = 0
}

/// The glass strip at the bottom of every screen (FT2): one visual that is the screen's own (Apps' trend, Calendar's
/// month, the drive, the chip, the battery), then the figures in equal columns across the strip, then an optional
/// control. Narrower, the figures alone; narrower still, in two rows. The numbers roll when `roll` changes.
struct ScreenFooter<Visual: View, Trailing: View, Roll: Equatable>: View {
    let figures: [FooterFigure]
    var roll: Roll
    @ViewBuilder let visual: Visual
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                visual.frame(width: 140, height: 32)
                Divider().frame(height: 30)
                columns(figures[...])
                trailing
            }
            HStack(spacing: 18) {
                columns(figures[...])
                trailing
            }
            let half = (figures.count + 1) / 2
            VStack(alignment: .leading, spacing: 8) {
                columns(figures[..<half])
                HStack(spacing: 18) {
                    columns(figures[half...])
                    trailing
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Layout.padding)
        .accessibilityElement(children: .contain)
    }

    private func columns(_ figures: ArraySlice<FooterFigure>) -> some View {
        HStack(alignment: .top, spacing: 18) {
            ForEach(figures) { figure in
                Figure(label: figure.label) {
                    HStack(spacing: 4) {
                        Text(figure.value)
                            .contentTransition(.numericText())
                            .animation(Motion.smooth(0.25), value: roll)
                        if figure.severity > 0 { SeverityIcon(severity: figure.severity) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(figure.help)
            }
        }
    }
}

extension ScreenFooter where Roll == Int {
    init(figures: [FooterFigure], @ViewBuilder visual: () -> Visual, @ViewBuilder trailing: () -> Trailing) {
        self.init(figures: figures, roll: 0, visual: visual, trailing: trailing)
    }
}

extension ScreenFooter where Roll == Int, Trailing == EmptyView {
    init(figures: [FooterFigure], @ViewBuilder visual: () -> Visual) {
        self.init(figures: figures, roll: 0, visual: visual, trailing: { EmptyView() })
    }
}

extension ScreenFooter where Trailing == EmptyView {
    init(figures: [FooterFigure], roll: Roll, @ViewBuilder visual: () -> Visual) {
        self.init(figures: figures, roll: roll, visual: visual, trailing: { EmptyView() })
    }
}

extension View {
    /// The screen's footer at the bottom of the content column, on glass and inset 8 pt; the content scrolls under it.
    /// None while `footer` is nil (the screen has no data yet).
    func screenFooter(_ footer: (some View)?) -> some View {
        safeAreaBar(edge: .bottom, spacing: 0) {
            if let footer { footer.frame(maxWidth: .infinity).floatingBar().padding(Layout.inset) }
        }
    }
}

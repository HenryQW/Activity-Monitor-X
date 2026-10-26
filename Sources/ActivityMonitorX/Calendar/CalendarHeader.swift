import AMXCore
import SwiftUI

/// The strip above the cells: the period, the time zone, the title, what the cells show, and the steps.
struct CalendarHeader: View {
    @Environment(CalendarModel.self) private var model
    @Environment(GroupsModel.self) private var groups
    @Environment(Preferences.self) private var preferences
    /// The period's title in full, shortened ("Oct 2026") and as the narrow forms show it.
    let title: String
    let shortTitle: String

    /// What a form keeps of the bar. The first form that fits the column is shown, so nothing is cut: the title shortens,
    /// then goes (the title pill names the period), then Show is an icon, then the period is a pop-up, then the pop-ups
    /// lose their indicator.
    private struct Fit {
        var title: String?
        var showName = true
        var segments = true
        /// Pop-ups lose their indicator.
        var compact = false
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(Fit(title: title))
            bar(Fit(title: shortTitle))
            bar(Fit())
            bar(Fit(showName: false))
            bar(Fit(showName: false, segments: false))
            bar(Fit(showName: false, segments: false, compact: true))
        }
        .frame(maxWidth: .infinity)
    }

    private func bar(_ form: Fit) -> some View {
        let name = model.period.rawValue.capitalized
        // Level 2 capsules: the period, the zone and the title, then what the cells show and the steps. The controls have
        // no bezel or track of their own: the capsule is their one glass (D71).
        return HStack(spacing: Layout.inset) {
            HStack(spacing: Layout.padding) {
                period(segments: form.segments, compact: form.compact)
                zoneMenu(compact: form.compact)
                if let title = form.title { Text(title).font(.headline).lineLimit(1).fixedSize() }
            }
            .floatingCapsule()
            Spacer(minLength: 0)
            HStack(spacing: Layout.inset) {
                showMenu(name: form.showName, compact: form.compact)
                Divider().padding(.vertical, Layout.padding)
                steps(name)
            }
            .floatingCapsule()
        }
    }

    /// Day, Week and Month as segments, or as a pop-up.
    private func period(segments: Bool, compact: Bool) -> some View {
        let selection = Binding<CalendarPeriod?>(
            // Hour is reached by zooming and has no segment.
            get: { model.period == .hour ? nil : model.period },
            set: { if let period = $0 { (model.period, model.selected) = (period, nil) } })
        return Group {
            if segments {
                CapsuleChoice(title: "Period", values: CalendarPeriod.strip, selection: selection) { Text($0.rawValue.capitalized) }
            } else {
                Picker("Period", selection: selection) {
                    ForEach(CalendarPeriod.strip, id: \.self) { Text($0.rawValue.capitalized).tag(Optional($0)) }
                }
                .labelsHidden()
                .fixedSize()
                .pickerStyle(.menu)
                .buttonStyle(.borderless)
                .menuIndicator(compact ? .hidden : .visible)
            }
        }
        .help("Choose the period")
    }

    private func steps(_ name: String) -> some View {
        HStack(spacing: Layout.inset) {
            Button("Previous \(name)", systemImage: "chevron.left") { model.step(-1) }
                .labelStyle(.iconOnly)
                .disabled(!model.canStep(-1))
                .help("Show the previous \(name.lowercased())")
            Button("Today") { model.anchor = Date() }
                .disabled(!model.canStep(1))
                .help("Show the \(name.lowercased()) that holds today")
            Button("Next \(name)", systemImage: "chevron.right") { model.step(1) }
                .labelStyle(.iconOnly)
                .disabled(!model.canStep(1))
                .help("Show the next \(name.lowercased())")
        }
        .buttonStyle(.borderless)
        .fixedSize()
    }

    // MARK: Time zone

    /// "HKT" while the view follows system time; "PDT, 15 h behind" with another zone forced.
    private func zoneMenu(compact: Bool) -> some View {
        let forced = preferences.timeZoneID.flatMap(TimeZone.init(identifier:))
        let system = AppTime.system
        return Menu {
            Picker("Time zone", selection: Bindable(preferences).timeZoneID) {
                Text("\(AppTime.title(of: nil)), system time").tag(String?.none)
                Section("Force one zone on the whole app") {
                    ForEach(ZoneLabel.common.filter { $0 != system.identifier }, id: \.self) { id in
                        Text(Self.title(id)).tag(Optional(id))
                    }
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            moreZones
            Divider()
            Section("Extra hour labels (Week, Day)") {
                ForEach(ZoneLabel.common.filter { $0 != system.identifier }, id: \.self) { id in
                    Toggle(ZoneLabel.abbreviation(TimeZone(identifier: id)!, at: Date()), isOn: extra(id))
                }
            }
        } label: {
            // Compact forms keep the abbreviation: the difference from system time would clip. The menu and hint name the zone.
            Text(compact ? ZoneLabel.abbreviation(forced ?? system, at: Date()) : AppTime.title(of: forced))
        }
        .buttonStyle(.borderless)
        .menuIndicator(compact ? .hidden : .visible)
        .fixedSize()
        .accessibilityLabel("Time zone")
        .help("Choose the time zone of the whole app: days and hours start at midnight in it. The data does not change.")
    }

    private static func title(_ id: String) -> String { AppTime.title(of: TimeZone(identifier: id)!) }

    /// Every zone, by region.
    private var moreZones: some View {
        let regions = Dictionary(grouping: TimeZone.knownTimeZoneIdentifiers.filter { $0.contains("/") }) { String($0.split(separator: "/")[0]) }
        return Menu("More Zones") {
            ForEach(regions.keys.sorted(), id: \.self) { region in
                Menu(region) {
                    Picker(region, selection: Bindable(preferences).timeZoneID) {
                        ForEach(regions[region]!.sorted(), id: \.self) { id in
                            Text(id.dropFirst(region.count + 1).replacingOccurrences(of: "_", with: " ")).tag(Optional(id))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
        }
    }

    private func extra(_ id: String) -> Binding<Bool> {
        Binding(get: { preferences.extraZoneIDs.contains(id) }, set: { on in
            preferences.extraZoneIDs.removeAll { $0 == id }
            if on { preferences.extraZoneIDs.append(id) }
        })
    }

    // MARK: Show

    private func showMenu(name shown: Bool, compact: Bool) -> some View {
        Menu {
            Picker("Show", selection: Bindable(model).show) {
                Text("Busiest App").tag(CalendarShow.busiest)
                Text("All Apps").tag(CalendarShow.all)
                if !groups.groups.isEmpty {
                    Section("Groups") {
                        ForEach(groups.groups) { group in
                            Label { Text(group.name) } icon: { Image(nsImage: GroupEditor.swatches[group.color]!) }.tag(CalendarShow.group(group.id))
                        }
                    }
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Divider()
            Text("Search for an app to see only its use.")
        } label: {
            if shown { Text("Show: \(CalendarView.showName(model.show, groups: groups.groups))") }
            else { Image(systemName: "line.3.horizontal.decrease") }
        }
        .buttonStyle(.borderless)
        .menuIndicator(compact ? .hidden : .visible)
        .fixedSize()
        .accessibilityLabel("Show")
        .help("Choose what each cell names: its busiest app, nothing, or the use of one group")
    }
}

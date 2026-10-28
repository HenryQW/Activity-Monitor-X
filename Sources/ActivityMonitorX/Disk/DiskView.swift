import AMXCore
import SwiftUI

/// Disk: the toolbar's Activity | Space segments switch the activity and the disk map (`DiskMapView`). The toolbar
/// items, the range bar (Activity only), the search and the inspector follow the pane.
struct DiskView: View {
    @Environment(Selection.self) private var selection

    var body: some View {
        Group {
            switch selection.diskPane {
            case .activity: DiskActivityView()
            case .space: DiskMapView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Activity | Space in the toolbar's centre, where Apps has Metric: the native segments at their own width, as the
/// screen's main switch.
struct DiskPanePicker: View {
    @Environment(Selection.self) private var selection

    var body: some View {
        Picker("View", selection: Bindable(selection).diskPane) {
            Text("Activity").tag(DiskPane.activity)
            Text("Space").tag(DiskPane.space)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("View")
        .help("Show the disk activity or the space that files use")
    }
}

/// All physical disks: history charts (Live from `DiskModel`, 1H to 90D from amxd's records), each disk with its SMART
/// health, the mounted volumes and the APFS containers. The search filters disks and volumes by name; a click selects one
/// for the inspector. Content layer: no glass.
private struct DiskActivityView: View {
    @Environment(AlertsModel.self) private var alerts
    @Environment(DiskModel.self) private var disk
    @Environment(DiskMapModel.self) private var diskMap
    @Environment(HistoryModel.self) private var history
    @Environment(Selection.self) private var selection
    /// Only the hidden columns are kept, as in the Apps table: a kept `TableColumnCustomization` also keeps each column's
    /// width, so a table narrower than the last pushes columns out of view.
    private let _columns = State(initialValue: DiskActivityView.customization())
    private static let hiddenKey = "diskVolumeHiddenColumns"
    private static let hideable = ["mountPoint"]

    private static func customization() -> TableColumnCustomization<VolumeInfo> {
        var columns = TableColumnCustomization<VolumeInfo>()
        for id in UserDefaults.standard.stringArray(forKey: hiddenKey) ?? [] { columns[visibility: id] = .hidden }
        return columns
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.section) {
                // The pill's column stays free of the charts, so it never covers a y-axis label.
                charts
                    .padding(.trailing, ChartZoom.width)
                    .overlay(alignment: .topTrailing) { ChartZoom().padding(.top, 24) }
                section("Physical Disks") { disks }
                section("Volumes") { volumes }
                section("APFS Containers") { containers }
            }
            .padding()
        }
        // The charts and lists scroll under the range bar.
        .safeAreaBar(edge: .top, spacing: 0) { RangeBar() }
        .screenFooter(disk.volumes.contains { $0.mountPoint == "/" } ? DiskFacts() : nil)
        .screenTitle("Disk", icon: .symbol("internaldrive"))
        // Stops with the screen: no disk reads while Disk is not shown.
        .task { await disk.run() }
        .onChange(of: selection.refreshes) { Task { await disk.refresh() } }
        .alert(disk.actionFailure?.title ?? "", isPresented: Binding(
            get: { disk.actionFailure != nil }, set: { if !$0 { disk.actionFailure = nil } })) {
            Button("OK") {}
        } message: {
            Text(disk.actionFailure?.message ?? "")
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.weight(.semibold))
            content()
        }
    }

    // MARK: Charts

    /// One time's values; `free` is nil where the record has none, and in Live.
    private struct Sample {
        let ts, read, write, iops, latency, util: Double
        let free: Double?
    }

    @ViewBuilder private var charts: some View {
        if history.range == .live {
            if let error = disk.error {
                ContentUnavailableView("Cannot Read Disks", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if disk.live.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            } else {
                grid(disk.live.map { Sample(ts: $0.ts, read: $0.total.readBps, write: $0.total.writeBps, iops: $0.total.iops,
                                            latency: $0.total.latencyMs, util: $0.total.utilPct, free: nil) }, live: true)
            }
        } else {
            switch history.state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            case .failed:
                HelperUnavailable()
            case .empty, .ready:
                grid(history.system.map { Sample(ts: $0.bucket, read: $0.diskR, write: $0.diskW, iops: $0.diskIOPS,
                                                 latency: $0.diskLatMs, util: $0.diskUtil, free: $0.diskFree) }, live: false)
            }
        }
    }

    private func grid(_ samples: [Sample], live: Bool) -> some View {
        let bucket = history.range.chartBucket
        // A line breaks where neighbouring records are more than a bucket apart (sleep, a paused window); 1.5 buckets
        // for Live's 1 s reads, which come a little over a second apart.
        var segment = 0
        let segments = samples.indices.map { i in
            if i > 0, samples[i].ts - samples[i - 1].ts > bucket * 1.5 { segment += 1 }
            return segment
        }
        func points(_ series: String, _ value: (Sample) -> Double) -> [DiskPoint] {
            samples.indices.map { DiskPoint(date: Self.date(samples[$0].ts), series: series, value: value(samples[$0]),
                                            segment: segments[$0]) }
        }
        // From min to max, at least a bucket wide: one sample, or a wall clock that stepped back, gives no valid range.
        let first = samples.map(\.ts).min() ?? 0
        let xDomain = Self.date(first)...Self.date(max(samples.map(\.ts).max() ?? 0, first + max(bucket, 1)))
        let throughput = zip(points("Read", \.read), points("Write", \.write)).flatMap { [$0, $1] }
        return Grid(horizontalSpacing: 24, verticalSpacing: 24) {
            GridRow {
                DiskChart(title: "Throughput", points: throughput, bucket: bucket, format: Metric.disk.format, xDomain: xDomain)
                DiskChart(title: "IOPS", points: points("IOPS", \.iops), bucket: bucket,
                          format: { $0.formatted(.number.precision(.fractionLength(0))) }, xDomain: xDomain)
            }
            GridRow {
                DiskChart(title: "Latency", points: points("Latency", \.latency), bucket: bucket,
                          format: { "\($0.formatted(.number.precision(.fractionLength(1)))) ms" }, xDomain: xDomain)
                DiskChart(title: "Utilisation", points: points("Utilisation", \.util), bucket: bucket,
                          format: { ($0 / 100).formatted(.percent.precision(.fractionLength(0))) }, xDomain: xDomain, yDomain: 0...100)
            }
            if !live {
                GridRow {
                    DiskChart(title: "Free (purgeable not included)", points: free(samples, segments: segments), bucket: bucket, format: Metric.bytes,
                              xDomain: xDomain, yDomain: capacity.map { 0...$0 },
                              rule: capacity.map { ($0, "Capacity \(Metric.bytes($0))") })
                        .gridCellColumns(2)
                }
            }
        }
    }

    private var capacity: Double? { disk.volumes.first { $0.mountPoint == "/" }.map { Double($0.totalBytes) } }

    /// The startup volume's free space; a record without a value also starts a new line segment.
    private func free(_ samples: [Sample], segments: [Int]) -> [DiskPoint] {
        var gaps = 0
        return samples.indices.compactMap { i in
            guard let free = samples[i].free else { gaps += 1; return nil }
            return DiskPoint(date: Self.date(samples[i].ts), series: "Free", value: free, segment: segments[i] + gaps)
        }
    }

    // MARK: Physical disks

    /// A cell for each disk, at most 3 to a row and more rows as needed; a later row keeps the first row's cell width.
    @ViewBuilder private var disks: some View {
        let disks = NameSearch.filter(disk.disks, query: selection.search) { [$0.model, $0.bsdName].compactMap { $0 } }
        if disks.isEmpty {
            Text(disk.disks.isEmpty ? "No physical disks found." : "No disk matches the search.").foregroundStyle(.secondary)
        } else {
            let columns = min(disks.count, 3)
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(Array(stride(from: 0, to: disks.count, by: columns)), id: \.self) { start in
                    GridRow { ForEach(disks[start..<min(start + columns, disks.count)]) { diskCell($0) } }
                }
            }
        }
    }

    /// The drive as Hardware draws it (SCR-19), the name and SMART state, kind and size, the used share and the rates now;
    /// a click selects the disk for the inspector, which has its SMART details.
    private func diskCell(_ d: PhysicalDisk) -> some View {
        let selected = disk.selected == .disk(d.bsdName)
        let space = d.space(volumes: disk.volumes, containers: disk.containers, rule: alerts.rules.freeSpace)
        let name = d.model ?? d.bsdName
        let kind = d.kind
        let used = space.share.map { "\(Int(($0 * 100).rounded()))% used" }
        let rate = disk.perDisk[d.bsdName]
        let health = disk.health[d.bsdName]?.isHealthy
        return Button { disk.selected = .disk(d.bsdName) } label: {
            HStack(spacing: Layout.inset) {
                FlashChips(count: space.startup ? 2 : 1, share: space.share, color: ChipDiagram.status(space.level)).frame(width: 32)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(name).fontWeight(.semibold)
                        if health == true { Image(systemName: "checkmark.seal").foregroundStyle(.secondary) }
                        if health == false { Image(systemName: "xmark.octagon.fill").foregroundStyle(.red) }
                    }
                    Text(kind)
                    HStack {
                        if let used { Text(used) }
                        Spacer(minLength: 6)
                        if let rate { Text("R \(Metric.disk.format(rate.readBps))  W \(Metric.disk.format(rate.writeBps))") }
                    }
                    .foregroundStyle(.secondary)
                }
                .lineLimit(1)
            }
            .font(.callout)
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .leading)
            .partCell(selected: selected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show \(name) in the inspector")
        .contextMenu {
            Group {
                Button("Show in Inspector", systemImage: "sidebar.trailing") {
                    disk.selected = .disk(d.bsdName)
                    selection.inspectorShown = true
                }
                .help("Show \(name) and its SMART details in the inspector")
                // One volume ejects the drive with all its volumes.
                if !d.isInternal, let volume = disk.volumes.first(where: { Volumes.wholeDisk(of: $0, containers: disk.containers) == d.bsdName }) {
                    Button("Eject", systemImage: "eject") { eject(volume) }
                        .help("Eject \(name) and all its volumes so that you can disconnect it safely")
                }
            }
            .labelStyle(.titleAndIcon)
        }
        .accessibilityLabel("Disk, \(name)")
        .accessibilityValue([kind, used, health == true ? "SMART verified" : health == false ? "SMART failing" : nil,
                             rate.map { "Read \(Metric.disk.format($0.readBps)), write \(Metric.disk.format($0.writeBps))" }]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }



    // MARK: Volumes

    @ViewBuilder private var volumes: some View {
        let volumes = NameSearch.filter(disk.volumes, query: selection.search) { [$0.name, $0.mountPoint] }
        let selected = Binding<VolumeInfo.ID?>(
            get: { if case .volume(let id) = disk.selected { id } else { nil } },
            set: { id in
                if let id { disk.selected = .volume(id) } else if case .volume = disk.selected { disk.selected = nil }
            })
        if volumes.isEmpty && !disk.volumes.isEmpty {
            Text("No volume matches the search.").foregroundStyle(.secondary)
        } else {
            table(volumes, selection: selected)
        }
    }

    private func table(_ volumes: [VolumeInfo], selection: Binding<VolumeInfo.ID?>) -> some View {
        Table(volumes, selection: selection, columnCustomization: _columns.projectedValue) {
            TableColumn("Name") { volume in
                Label(volume.name, systemImage: volume.isInternal ? "internaldrive" : "externaldrive")
            }
            TableColumn("Kind") { Text($0.role ?? $0.fileSystem.uppercased()) }
                .width(ideal: 80)
            TableColumn("Capacity") { Text(Metric.bytes(Double($0.totalBytes))).monospacedDigit() }
                .width(ideal: 90)
            TableColumn("Used") { UsedCell(volume: $0) }
                .width(min: 140, ideal: 160)
            TableColumn("Available") { Text(Metric.bytes(Double($0.availableBytes ?? $0.freeBytes))).monospacedDigit() }
                .width(ideal: 90)
            TableColumn("Encrypted") { Text($0.isEncrypted ? "Yes" : "No") }
                .width(ideal: 70)
            TableColumn("Mount Point", value: \.mountPoint)
                .width(ideal: 100)
                .customizationID("mountPoint")
        }
        // Show in Space: the menu, or a double-click.
        .contextMenu(forSelectionType: VolumeInfo.ID.self) { ids in
            if ids.count == 1, let volume = volumes.first(where: { $0.id == ids.first }) {
                Group {
                    Button("Show in Space", systemImage: "chart.pie") { showInSpace(volume) }
                        .help("Show what uses the space on \(volume.name)")
                    ShowInFinderButton(path: volume.mountPoint, help: "Show \(volume.name) in the Finder")
                    Button("Copy Mount Point", systemImage: "doc.on.doc") { DiskItemMenu.copy(volume.mountPoint) }
                        .help("Copy \(volume.mountPoint)")
                    if !volume.isInternal {
                        Divider()
                        Button("Eject", systemImage: "eject") { eject(volume) }
                            .help("Eject \(volume.name) so that you can disconnect it safely")
                    }
                }
                .labelStyle(.titleAndIcon)
            }
        } primaryAction: { ids in
            if ids.count == 1, let volume = volumes.first(where: { $0.id == ids.first }) { showInSpace(volume) }
        }
        // Inside the page's scroll view: as tall as its rows, scrolled with the page.
        .frame(height: Self.tableHeight(rows: volumes.count, row: 24))
        .scrollDisabled(true)
        .onChange(of: _columns.wrappedValue) { _, columns in
            UserDefaults.standard.set(Self.hideable.filter { columns[visibility: $0] == .hidden }, forKey: Self.hiddenKey)
        }
    }

    /// Reads the disks again at once, so the ejected volume goes.
    private func eject(_ volume: VolumeInfo) {
        Task {
            disk.actionFailure = await volume.eject()
            await disk.refresh()
        }
    }

    /// Opens the Space pill on the volume's map.
    private func showInSpace(_ volume: VolumeInfo) {
        diskMap.open(.volume(volume))
        selection.diskPane = .space
    }

    // MARK: APFS containers

    /// A table as the Volumes table: one row per container, its volumes named once (a role that only repeats the name
    /// is left out).
    @ViewBuilder private var containers: some View {
        if disk.containers.isEmpty {
            Text("No APFS containers found.").foregroundStyle(.secondary)
        } else {
            Table(disk.containers) {
                TableColumn("Name") { Label($0.bsdName, systemImage: "square.stack.3d.up") }
                    .width(min: 80, ideal: 100, max: 140)
                TableColumn("Physical Store") { Text($0.physicalStores.joined(separator: ", ")) }
                    .width(min: 90, ideal: 110, max: 140)
                TableColumn("Size") { Text(Metric.bytes(Double($0.sizeBytes))).monospacedDigit() }
                    .width(min: 70, ideal: 90, max: 120)
                TableColumn("Free") { Text($0.freeBytes.map { Metric.bytes(Double($0)) } ?? "Unknown").monospacedDigit() }
                    .width(min: 70, ideal: 90, max: 120)
                TableColumn("Volumes") { c in
                    let names = c.volumes.map { m in
                        m.role.map { $0 == m.name ? m.name : "\(m.name) (\($0))" } ?? m.name
                    }
                    .joined(separator: ", ")
                    Text(names).help(names)
                }
            }
            .frame(height: Self.tableHeight(rows: disk.containers.count, row: 25.5))
            .scrollDisabled(true)
        }
    }

    /// The height of a table with no scrolling of its own: the header and its rows (measured: 33 pt for the header,
    /// 24 pt a volume row, 25.5 pt a container row, whose symbol is taller).
    private static func tableHeight(rows: Int, row: CGFloat) -> CGFloat { CGFloat(rows) * row + 33 }

    private static func date(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }
}

/// "Verified", "Failing" in red, or "Not available" for a disk without a SMART log.
struct SmartStatus: View {
    let health: NVMeHealth?

    var body: some View {
        switch health?.isHealthy {
        case true?: Label("Verified", systemImage: "checkmark.seal")
        case false?: Label("Failing", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
        case nil: Text("Not available").foregroundStyle(.secondary)
        }
    }
}

extension PhysicalDisk {
    /// "Internal Apple Fabric, 1 TB": the Disk cell's and the Hardware drive row's.
    var kind: String { (isInternal ? "Internal" : "External") + (protocolName.map { " \($0)" } ?? "") + ", " + Metric.bytes(Double(sizeBytes)) }

    /// The used share from the disk's volumes: an APFS container once (its size less its free space, as Hardware's
    /// startup volume; else its largest volume use, which "/" gives for the whole container), another volume by its own
    /// use; the highest status level of those volumes; and whether it holds "/", which Hardware draws with two chips.
    /// Nil share with no volume.
    func space(volumes all: [VolumeInfo], containers: [APFSContainer], rule: AlertRules.FreeSpace) -> (share: Double?, level: Int, startup: Bool) {
        let volumes = all.filter { Volumes.wholeDisk(of: $0, containers: containers) == bsdName }
        let startup = volumes.contains { $0.mountPoint == "/" }
        guard !volumes.isEmpty, sizeBytes > 0 else { return (nil, 0, startup) }
        let used = Dictionary(grouping: volumes) { $0.container ?? $0.id }.reduce(0.0) { sum, pool in
            let container = containers.first { $0.bsdName == pool.key }.flatMap { c in c.freeBytes.map { c.sizeBytes - min($0, c.sizeBytes) } }
            return sum + Double(container ?? pool.value.map { min($0.used, $0.totalBytes) }.max() ?? 0)
        }
        return (min(used / Double(sizeBytes), 1), volumes.map { $0.spaceLevel(rule) }.max() ?? 0, startup)
    }
}

extension VolumeInfo {
    var used: UInt64 { usedBytes ?? totalBytes - min(freeBytes, totalBytes) }
    var available: UInt64 { availableBytes ?? freeBytes }

    /// Unmounts the volume and ejects its drive, with the drive's other volumes; the failure's title and message, if any.
    /// Off the main actor: a busy drive can take seconds to flush.
    func eject() async -> (title: String, message: String)? {
        let (mount, name) = (mountPoint, self.name)
        return await Task.detached {
            do { try NSWorkspace.shared.unmountAndEjectDevice(at: URL(filePath: mount)) } catch {
                return ("Cannot Eject \(name)", error.localizedDescription)
            }
            return nil
        }.value
    }
    /// Free space under 15 % of the capacity, or on the startup volume under the Mac's memory (room to swap): the bar is
    /// yellow (warning). A small external drive is not low because it holds less than the memory.
    var lowSpace: Bool {
        Double(available) < Double(totalBytes) * 0.15 || mountPoint == "/" && available < ProcessInfo.processInfo.physicalMemory
    }
    /// 2 on the startup volume at the free space alert's level, 1 on low space, else 0: the drawn drive's status colour.
    func spaceLevel(_ rule: AlertRules.FreeSpace) -> Int {
        let critical = mountPoint == "/" && rule.enabled && Double(available) <= Double(totalBytes) * Double(rule.percentFree) / 100
        return critical ? 2 : lowSpace ? 1 : 0
    }
}

/// Used bytes with a bar, yellow on low space.
private struct UsedCell: View {
    let volume: VolumeInfo

    var body: some View {
        let total = volume.totalBytes
        let used = volume.used
        let low = volume.lowSpace
        HStack {
            if total > 0 {
                ProgressView(value: Double(min(used, total)), total: Double(total))
                    .tint(low ? .yellow : nil)
                    // The small bar keeps the row at the standard table height that `tableHeight` counts.
                    .controlSize(.small)
                    .frame(width: 60)
                    .accessibilityLabel(low ? "Low free space" : "Used")
            }
            Text(Metric.bytes(Double(used))).monospacedDigit()
        }
    }
}

/// The startup disk at a glance in the screen's footer (FT2): its drawing filled to its use, then the startup volume's
/// free space, the read and write rates now and its SMART health.
private struct DiskFacts: View {
    @Environment(AlertsModel.self) private var alerts
    @Environment(DiskModel.self) private var disk

    var body: some View {
        let startup = disk.volumes.first { $0.mountPoint == "/" }!
        let drive = disk.disks.first { Volumes.wholeDisk(of: startup, containers: disk.containers) == $0.bsdName }
        let space = drive?.space(volumes: disk.volumes, containers: disk.containers, rule: alerts.rules.freeSpace)
        let rate = disk.live.last?.total
        let health = drive.flatMap { disk.health[$0.bsdName]?.isHealthy }
        let bytes = Metric.memory.format
        ScreenFooter(figures: [
            FooterFigure(label: "Free of \(bytes(Double(startup.totalBytes)))", value: bytes(Double(startup.freeBytes)),
                         help: "The free space on \(startup.name), purgeable space not included", severity: startup.spaceLevel(alerts.rules.freeSpace)),
            FooterFigure(label: "Read now", value: rate.map { Metric.disk.format($0.readBps) } ?? "Reading…", help: "Bytes read per second by all disks"),
            FooterFigure(label: "Write now", value: rate.map { Metric.disk.format($0.writeBps) } ?? "Reading…", help: "Bytes written per second by all disks"),
            FooterFigure(label: "Drive health", value: health.map { $0 ? "Verified" : "Failing" } ?? "Not available",
                         help: "The startup disk's SMART status", severity: health == false ? 2 : 0),
        ]) {
            FlashChips(count: 2, share: space?.share, color: ChipDiagram.status(space?.level ?? 0)).frame(height: 32)
        }
        .accessibilityLabel("Startup disk summary")
    }
}

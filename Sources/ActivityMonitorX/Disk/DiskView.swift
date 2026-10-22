import AMXCore
import SwiftUI

/// All physical disks: history charts (Live from `DiskModel`, 1H to 90D from amxd's records), each disk with its SMART
/// health, the mounted volumes and the APFS containers. The search filters disks and volumes by name; a click selects one
/// for the inspector. Content layer: no glass.
struct DiskView: View {
    @Environment(DiskModel.self) private var disk
    @Environment(HistoryModel.self) private var history
    @Environment(Selection.self) private var selection
    @SceneStorage("diskVolumeColumns") private var columns = TableColumnCustomization<VolumeInfo>()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                charts
                section("Physical Disks") { disks }
                section("Volumes") { volumes }
                section("APFS Containers") { containers }
            }
            .padding()
        }
        .navigationTitle("Disk")
        .navigationSubtitle(["All physical disks", history.subtitle].filter { !$0.isEmpty }.joined(separator: " · "))
        // Stops with the screen: no disk reads while Disk is not shown.
        .task { await disk.run() }
        .onChange(of: selection.refreshes) { Task { await disk.refresh() } }
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

    @ViewBuilder private var disks: some View {
        let disks = NameSearch.filter(disk.disks, query: selection.search) { [$0.model, $0.bsdName].compactMap { $0 } }
        if disks.isEmpty {
            Text(disk.disks.isEmpty ? "No physical disks found." : "No disk matches the search.").foregroundStyle(.secondary)
        } else {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(disks) { d in
                        if let health = disk.health[d.bsdName] {
                            DisclosureGroup { healthDetails(health) } label: { diskRow(d) }
                        } else {
                            diskRow(d)
                        }
                    }
                }
                .padding(4)
            }
        }
    }

    /// A click selects the disk; the selected row has the selection background.
    private func diskRow(_ d: PhysicalDisk) -> some View {
        let selected = disk.selected == .disk(d.bsdName)
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(d.model ?? d.bsdName).fontWeight(.medium)
                Text([d.protocolName, d.isInternal ? "Internal" : "External", Metric.bytes(Double(d.sizeBytes))]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let rate = disk.perDisk[d.bsdName] {
                Text("Read \(Metric.disk.format(rate.readBps)) · Write \(Metric.disk.format(rate.writeBps))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            SmartStatus(health: disk.health[d.bsdName])
                .frame(minWidth: 110, alignment: .leading)
        }
        .padding(4)
        .background(selected ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { disk.selected = .disk(d.bsdName) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { disk.selected = .disk(d.bsdName) }
    }

    private func healthDetails(_ h: NVMeHealth) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            detail("Percentage used", Self.percent(h.percentageUsed))
            detail("Available spare", "\(Self.percent(h.availableSpare)) (threshold \(Self.percent(h.spareThreshold)))")
            detail("Temperature", h.temperatureCelsius.map { "\(Int($0.rounded())) °C" } ?? "Unknown")
            detail("Data read", Metric.bytes(Double(h.dataReadBytes)))
            detail("Data written", Metric.bytes(Double(h.dataWrittenBytes)))
            detail("Power-on hours", h.powerOnHours.formatted())
            detail("Power cycles", h.powerCycles.formatted())
            detail("Unsafe shutdowns", h.unsafeShutdowns.formatted())
            detail("Media errors", h.mediaErrors.formatted())
        }
        .padding(.leading, 4)
        .padding(.vertical, 4)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
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
        Table(volumes, selection: selection, columnCustomization: $columns) {
            TableColumn("Name", value: \.name)
            TableColumn("Kind") { Text($0.role ?? $0.fileSystem.uppercased()) }
            TableColumn("Capacity") { Text(Metric.bytes(Double($0.totalBytes))).monospacedDigit() }
            TableColumn("Used") { UsedCell(volume: $0) }
                .width(min: 140, ideal: 170)
            TableColumn("Available") { Text(Metric.bytes(Double($0.availableBytes ?? $0.freeBytes))).monospacedDigit() }
            TableColumn("Encrypted") { Text($0.isEncrypted ? "Yes" : "No") }
            TableColumn("Mount Point", value: \.mountPoint)
                .customizationID("mountPoint")
        }
        // Inside the page's scroll view: as tall as its rows, scrolled with the page.
        .frame(height: CGFloat(volumes.count) * 24 + 32)
        .scrollDisabled(true)
    }

    // MARK: APFS containers

    @ViewBuilder private var containers: some View {
        if disk.containers.isEmpty {
            Text("No APFS containers found.").foregroundStyle(.secondary)
        } else {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(disk.containers) { c in
                        DisclosureGroup {
                            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 4) {
                                detail("Size", Metric.bytes(Double(c.sizeBytes)))
                                detail("Free", c.freeBytes.map { Metric.bytes(Double($0)) } ?? "Unknown")
                                detail("Physical stores", c.physicalStores.joined(separator: ", "))
                                GridRow {
                                    Text("Volumes").foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        ForEach(c.volumes, id: \.bsdName) { m in
                                            Text(([m.name] + [m.role, m.isEncrypted ? "Encrypted" : nil].compactMap { $0 })
                                                .joined(separator: " · "))
                                        }
                                    }
                                }
                            }
                            .padding(.leading, 4)
                            .padding(.vertical, 4)
                        } label: {
                            Text("\(c.bsdName) · \(Metric.bytes(Double(c.sizeBytes)))").fontWeight(.medium)
                        }
                    }
                }
                .padding(4)
            }
        }
    }

    private static func date(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }

    private static func percent(_ value: Int) -> String { (Double(value) / 100).formatted(.percent) }
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

extension VolumeInfo {
    var used: UInt64 { usedBytes ?? totalBytes - min(freeBytes, totalBytes) }
    var available: UInt64 { availableBytes ?? freeBytes }
    /// Free space under 15 % of the capacity or under the Mac's memory: the bar is orange.
    var lowSpace: Bool { Double(available) < Double(totalBytes) * 0.15 || available < ProcessInfo.processInfo.physicalMemory }
}

/// Used bytes with a bar, orange on low space.
private struct UsedCell: View {
    let volume: VolumeInfo

    var body: some View {
        let total = volume.totalBytes
        let used = volume.used
        let low = volume.lowSpace
        HStack {
            if total > 0 {
                ProgressView(value: Double(min(used, total)), total: Double(total))
                    .tint(low ? .orange : nil)
                    .frame(width: 60)
                    .accessibilityLabel(low ? "Low free space" : "Used")
            }
            Text(Metric.bytes(Double(used))).monospacedDigit()
        }
    }
}

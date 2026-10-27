import Foundation

/// One time bucket of the Calendar: the metric summed over the processes as a mean rate, and each app's part of it.
public struct CalendarBucket: Sendable, Equatable {
    /// nil where no process has data, as in a time of no width.
    public let total: Double?
    public let apps: [AppKey: Double]

    public init(total: Double?, apps: [AppKey: Double] = [:]) { (self.total, self.apps) = (total, apps) }

    /// For each `bounds[i]..<bounds[i + 1]` (ascending), the metric of `tracks` averaged over that time, a gap counting as 0.
    public static func read(_ tracks: [ProcessTrack], bounds: [Double]) -> [CalendarBucket] {
        guard bounds.count > 1 else { return [] }
        var sums = [[AppKey: Double]](repeating: [:], count: bounds.count - 1), seen = [Bool](repeating: false, count: bounds.count - 1)
        for track in tracks {
            // Slices are in time order inside the bounds: each starts in the interval of the last or a later one.
            var i = 0
            for slice in track.slices {
                while bounds[i + 1] <= slice.start { i += 1 }
                var j = i
                while j < sums.count, bounds[j] < slice.end {
                    let overlap = min(slice.end, bounds[j + 1]) - max(slice.start, bounds[j])
                    if overlap > 0 {
                        sums[j][track.app, default: 0] += slice.value * overlap
                        seen[j] = true
                    }
                    j += 1
                }
            }
        }
        return sums.indices.map { j in
            let width = bounds[j + 1] - bounds[j]
            guard seen[j] else { return CalendarBucket(total: nil) }
            let apps = sums[j].mapValues { $0 / width }
            return CalendarBucket(total: apps.values.reduce(0, +), apps: apps)
        }
    }
}

/// What the Calendar colours. CPU: the system CPU rule's warning and critical levels, drawn as lines, and the level each
/// bucket's whole-Mac CPU reached. Memory: the memory pressure each bucket recorded, with no line. Other metrics have none.
public struct CalendarStatus: Sendable, Equatable {
    /// The CPU levels in the metric's unit (a share of one core, so the rule's share of all cores times the core count);
    /// nil for memory.
    public let warn: Double?
    public let critical: Double?
    /// The severity (1 warning, 2 critical) of each bucket start, from the system tier; a start not listed was normal.
    private let pressure: [Double: Int]

    /// nil for a metric without status, and for CPU while the system CPU rule is off. `pressure` is the highest kernel
    /// pressure level (1, 2 or 4) of each bucket, and `cpu` the mean machine CPU (% of all cores), by the bucket's start.
    public init?(metric: Metric, rules: AlertRules, device: Device, pressure: [Double: Int] = [:], cpu: [Double: Double] = [:]) {
        switch metric {
        case .cpu:
            guard rules.systemCPU.enabled else { return nil }
            (warn, critical) = (Double(rules.systemCPU.warning * device.cores), Double(rules.systemCPU.critical * device.cores))
            let rule = rules.systemCPU
            self.pressure = cpu.mapValues { $0 >= Double(rule.critical) ? 2 : $0 >= Double(rule.warning) ? 1 : 0 }
        case .memory:
            (warn, critical) = (nil, nil)
            self.pressure = pressure.mapValues { $0 >= 4 ? 2 : $0 == 2 ? 1 : 0 }
        default: return nil
        }
    }

    /// 0 normal, 1 warning, 2 critical: what the system tier recorded for the bucket at `start`, whatever the apps shown.
    public func severity(_ value: Double, at start: Double) -> Int { pressure[start] ?? 0 }

    /// The severity of each bucket of `values` (the first starts at `start`, each `bucket` seconds wide); nil with no data.
    public func severities(_ values: [Double?], start: Double, bucket: Double) -> [Int?] {
        values.enumerated().map { i, value in value.map { severity($0, at: start + Double(i) * bucket) } }
    }

    public func severities(_ cell: CalendarCell) -> [Int?] { severities(cell.lines, start: cell.start, bucket: cell.bucket) }

    /// The buckets at the warning level and at the critical level.
    public func counts(_ values: [Double?], start: Double, bucket: Double) -> (warning: Int, critical: Int) {
        Self.counts(severities(values, start: start, bucket: bucket))
    }

    public func counts(_ cells: [CalendarCell]) -> (warning: Int, critical: Int) { Self.counts(cells.flatMap(severities)) }

    private static func counts(_ severities: [Int?]) -> (warning: Int, critical: Int) {
        let all = severities.compactMap { $0 }
        return (all.count { $0 == 1 }, all.count { $0 == 2 })
    }
}

/// The usual total by weekday and hour of day over a past window, which the Calendar compares a cell with.
public struct CalendarUsual: Sendable {
    private var sums = [Double](repeating: 0, count: 7 * 24)
    private var counts = [Int](repeating: 0, count: 7 * 24)
    private let calendar: Calendar

    /// `totals[i]` is the hour starting at `start` + i hours. Each weekday and hour needs 2 hours of data to have a usual value.
    public init(totals: [Double?], start: Double, calendar: Calendar) {
        self.calendar = calendar
        for (i, total) in totals.enumerated() {
            guard let total else { continue }
            let slot = Self.slot(Date(timeIntervalSince1970: start + Double(i) * 3600), calendar)
            sums[slot] += total
            counts[slot] += 1
        }
    }

    private static func slot(_ date: Date, _ calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) - 1) * 24 + calendar.component(.hour, from: date)
    }

    /// The mean of the usual values of the hours in [from, to) (on their own weekdays); nil when an hour has too little history.
    public func value(from: Double, to: Double) -> Double? {
        var total = 0.0, hours = 0.0, t = from
        while t < to {
            let slot = Self.slot(Date(timeIntervalSince1970: t), calendar), seconds = min(((t / 3600).rounded(.down) + 1) * 3600, to) - t
            guard counts[slot] >= 2 else { return nil }
            total += seconds * sums[slot] / Double(counts[slot])
            hours += seconds
            t += seconds
        }
        return hours > 0 ? total / hours : nil
    }
}

/// A span of hours as numbers: what the inspector sets against the span before it.
public struct SpanStats: Sendable, Equatable {
    public let average: Double?
    public let peak: Double?
    /// The start of the hour of the peak.
    public let peakAt: Double?
    public let warning: Int
    public let critical: Int
    /// The mean of each day, or of each hour in a span under two days.
    public let units: [Double?]

    /// `hours[i]` is the total of the hour starting at `start` + i hours; `calendar` bounds the days.
    public init(hours: [Double?], start: Double, status: CalendarStatus?, calendar: Calendar) {
        let values = hours.compactMap { $0 }
        average = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        let top = hours.indices.filter { hours[$0] != nil }.max { hours[$0]! < hours[$1]! }
        (peak, peakAt) = (top.map { hours[$0]! }, top.map { start + Double($0) * 3600 })
        (warning, critical) = status?.counts(hours, start: start, bucket: 3600) ?? (0, 0)
        // A span of two days or more by calendar day (a day with a DST change has 23 or 25 hours), else by hour.
        var groups: [[Double?]] = []
        var day: Date?
        for (i, hour) in hours.enumerated() {
            let date = Date(timeIntervalSince1970: start + Double(i) * 3600)
            let key = hours.count >= 48 ? calendar.startOfDay(for: date) : date
            if key == day { groups[groups.count - 1].append(hour) } else { groups.append([hour]) }
            day = key
        }
        units = groups.map { group in
            let part = group.compactMap { $0 }
            return part.isEmpty ? nil : part.reduce(0, +) / Double(part.count)
        }
    }
}

extension CalendarPeriod {
    /// The app with the largest mean over `cells` and its share of their total, each cell weighing its buckets with data;
    /// nil with no data. Only the cells' top apps count.
    public static func leader(of cells: [CalendarCell]) -> (app: AppKey, share: Double)? {
        var sums: [AppKey: Double] = [:], total = 0.0
        for cell in cells {
            guard let value = cell.value else { continue }
            let weight = Double(cell.lines.count { $0 != nil })
            total += value * weight
            for entry in cell.top { sums[entry.app, default: 0] += entry.value * weight }
        }
        guard total > 0, let top = sums.max(by: { ($0.value, $1.key.key) < ($1.value, $0.key.key) }) else { return nil }
        return (top.key, top.value / total)
    }
}

extension HistoryReader {
    /// The buckets of `tracks` over `bounds` (as `CalendarBucket.read`). With every app shown, a CPU total is the Mac's
    /// recorded CPU where the system tier has it, so a line, its status colour and the level lines are one measure (CB1);
    /// the recorded processes sum lower (short-lived processes, time between samples). The apps stay as recorded.
    public func calendarBuckets(_ tracks: [ProcessTrack], metric: Metric, everyApp: Bool, source: HistorySource,
                                bounds: [Double], bucket: Double) throws -> [CalendarBucket] {
        let buckets = CalendarBucket.read(tracks, bounds: bounds)
        guard metric == .cpu, everyApp, bounds.count > 1 else { return buckets }
        let points = try system(source: source, from: bounds[0], to: bounds[bounds.count - 1], bucket: bucket)
        let mac = Dictionary(uniqueKeysWithValues: points.map { ($0.bucket, $0.cpu * Double(device.cores)) })
        return buckets.enumerated().map { i, b in CalendarBucket(total: mac[bounds[i]] ?? b.total, apps: b.apps) }
    }

    /// The status of `metric` for buckets of `bucket` seconds over [from, to) of `source`; memory reads the pressure and CPU
    /// the machine CPU each bucket recorded.
    public func calendarStatus(metric: Metric, rules: AlertRules, source: HistorySource, from: Double, to: Double,
                               bucket: Double) throws -> CalendarStatus? {
        let points = try metric == .cpu || metric == .memory ? system(source: source, from: from, to: to, bucket: bucket) : []
        return CalendarStatus(metric: metric, rules: rules, device: device,
                              pressure: metric == .memory ? Dictionary(uniqueKeysWithValues: points.map { ($0.bucket, $0.pressureLevel) }) : [:],
                              cpu: Dictionary(uniqueKeysWithValues: points.map { ($0.bucket, $0.cpu) }))
    }
}

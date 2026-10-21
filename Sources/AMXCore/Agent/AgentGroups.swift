import Foundation

/// Group tools: the user's groups with their current score, and one group's series and members.
enum AgentGroups {
    static let tools = [listGroups, groupSummary]

    // MARK: list_groups

    struct NoArguments: Decodable {}
    struct Group: Encodable {
        let id: UUID, name: String, symbol: String, color: GroupColor, rule: GroupRule, scoreNow: Double
    }
    struct Groups: Encodable { let groups: [Group] }

    static let listGroups = AgentTools.Tool(
        "list_groups",
        """
        The user's process groups. rule is the match rule: {"all":[…]}, {"any":[…]}, {"not":{…}} or a condition \
        {"field": name|bundle_id|path|team_id, "op": is|contains|starts_with, "value": …}, case-insensitive. \
        score_now is the sum of the members' mean score over the last 60 s. \(Metric.score.unit).
        """,
        schema: AgentTools.schema([])
    ) { (_: NoArguments, context) -> Groups in
        let groups = try context.groups()
        let now = context.now()
        let tracks = try context.reader.tracks(source: .raw, from: now - 60, to: now, metric: .score)
        let scores = GroupScores.averages(tracks, groups: groups, from: now - 60, to: now)
        return Groups(groups: groups.map {
            Group(id: $0.id, name: $0.name, symbol: $0.symbol, color: $0.color, rule: $0.rule, scoreNow: scores[$0.id]!)
        })
    }

    // MARK: group_summary

    struct SummaryArguments: Decodable { let group: String; let from, to: AgentTools.Time?; let metric: String? }
    /// Apps that share a name are summed, as in app_history.
    struct Member: Encodable { let app: String, appKeys: [String], average: Double, share: Double }
    struct Summary: Encodable {
        let group: String, metric: String, unit: String, bucketSeconds: Double
        let points: [AgentHistory.Point], members: [Member]
    }

    static let groupSummary = AgentTools.Tool(
        "group_summary",
        """
        One group's series and member apps over the window. points has at most 120 points, each the members' summed \
        mean over the bucket starting at t; members are ranked by their time-weighted average; share is the app's part \
        of the group total. group is a group id or name, case-insensitive. metric defaults to score. \
        \(AgentTools.units) \(AgentTools.times)
        """,
        schema: AgentTools.schema([#""group":{"type":"string"}"#, AgentTools.timeProperties,
                                   AgentTools.metricProperty(default: .score)],
                                  required: ["group"])
    ) { (a: SummaryArguments, context) -> Summary in
        let group = try find(a.group, in: context.groups())
        let metric = try AgentTools.metric(a.metric ?? "score")
        let w = try AgentTools.window(from: a.from, to: a.to, context: context)
        let (tracks, from) = try AgentHistory.load(w, metric, context)
        let members = GroupScores.members(tracks, of: group)
        let apps = Dictionary(grouping: AppSeries.ranking(members, from: from, to: w.to, bucket: w.bucket), by: \.app.name)
            .map { name, ranks in (name, ranks.map(\.app.key).sorted(), ranks.reduce(0) { $0 + $1.average }) }
            .sorted { ($1.2, $0.0) < ($0.2, $1.0) }
        let total = apps.reduce(0) { $0 + $1.2 }
        return Summary(group: group.name, metric: metric.rawValue, unit: metric.unit, bucketSeconds: w.bucket,
                       points: AgentHistory.points(members, from: from, w),
                       members: apps.map { Member(app: $0.0, appKeys: $0.1, average: $0.2, share: total > 0 ? $0.2 / total : 0) })
    }

    static func find(_ text: String, in groups: [ProcessGroup]) throws -> ProcessGroup {
        let matched = groups.filter { $0.id == UUID(uuidString: text) || $0.name.caseInsensitiveCompare(text) == .orderedSame }
        guard matched.count < 2 else { throw AgentError.invalid("ambiguous group: \(text)") }
        guard let group = matched.first else { throw AgentError.invalid("unknown group: \(text)") }
        return group
    }
}

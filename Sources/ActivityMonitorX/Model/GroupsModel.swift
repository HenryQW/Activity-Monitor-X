import AMXCore
import Foundation
import Observation

/// The user's process groups from `groups.json` and their score over the last 60 s.
@Observable @MainActor
final class GroupsModel {
    private(set) var groups: [ProcessGroup] = []
    /// Set when `groups.json` exists but could not be read, at launch or before a save; a save never overwrites
    /// a file it cannot read.
    private(set) var loadError: String?
    private(set) var scores: [UUID: Double] = [:]

    private let url: URL
    private let history: HistoryModel
    private var scoring = 0

    init(history: HistoryModel, url: URL = GroupStore.defaultURL) {
        (self.history, self.url) = (history, url)
        do {
            groups = try GroupStore.load(from: url)
        } catch {
            loadError = "\(url.path): \(error.localizedDescription)"
        }
    }

    /// Inserts the group or replaces the one with its id.
    func save(_ group: ProcessGroup) throws {
        try write { groups in
            if let i = groups.firstIndex(where: { $0.id == group.id }) { groups[i] = group } else { groups.append(group) }
        }
        Task { await score() }
    }

    func delete(_ id: UUID) throws {
        try write { $0.removeAll { $0.id == id } }
    }

    /// Raw history of the last 60 s, CPU: the processes a rule can match now.
    func recentProcesses() async throws -> [ProcessTrack] {
        let now = Date().timeIntervalSince1970
        return try await history.rawTracks(metric: .cpu, from: now - 60, to: now)
    }

    /// Runs while a window is open: scores now, then every 15 s while it shows on screen, as often as the raw tier gains rows.
    func run() async {
        await score()
        while (try? await Task.sleep(for: .seconds(15))) != nil {
            if MainWindowRef.windowShown { await score() }
        }
    }

    /// Applies `change` to the file as it is now, so a hand edit made while the app runs is kept.
    private func write(_ change: (inout [ProcessGroup]) -> Void) throws {
        var fresh: [ProcessGroup]
        do {
            fresh = try GroupStore.load(from: url)
        } catch {
            let reason = "\(url.path): \(error.localizedDescription)"
            loadError = reason
            throw Unavailable(reason: reason)
        }
        change(&fresh)
        try GroupStore.save(fresh, to: url)
        (groups, loadError) = (fresh, nil)
    }

    /// Without the history database the badges stay as they are; the group screen shows the error.
    /// A save scores at once while the loop may be scoring too; only the newest run sets `scores`.
    private func score() async {
        guard !groups.isEmpty else { return }
        scoring += 1
        let (generation, groups, now) = (scoring, groups, Date().timeIntervalSince1970)
        guard let tracks = try? await history.rawTracks(metric: .score, from: now - 60, to: now),
              generation == scoring else { return }
        scores = GroupScores.averages(tracks, groups: groups, from: now - 60, to: now)
    }

    private struct Unavailable: LocalizedError {
        let reason: String
        var errorDescription: String? { "groups.json could not be read, so it is not overwritten: \(reason)" }
    }
}

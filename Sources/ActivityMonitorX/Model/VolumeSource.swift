import AMXCore

/// The one volume read of the app, shared by Disk, Disk Map and Hardware. A dead network mount can block it for long;
/// every caller waits for the read in flight instead of starting another, so blocked reads never pile up.
@MainActor
final class VolumeSource {
    private var inFlight: Task<(volumes: [VolumeInfo], containers: [APFSContainer]), Never>?

    func read() async -> (volumes: [VolumeInfo], containers: [APFSContainer]) {
        let read = inFlight ?? Task.detached { Volumes.read() }
        inFlight = read
        let result = await read.value
        if inFlight == read { inFlight = nil }
        return result
    }
}

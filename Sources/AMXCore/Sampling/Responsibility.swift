import CAMX

/// The process macOS holds responsible for a pid (the app that launched it, for TCC and similar).
public enum Responsibility {
    /// nil when there is no other responsible process or it has exited.
    public static func responsiblePath(of pid: Int32) -> String? {
        let responsible = camx_responsible_pid(pid)
        guard responsible >= 1, responsible != pid else { return nil }
        return ProcessReader.path(pid: responsible)
    }
}

/// What fills a disk, for the Space treemap's colours: from a name's extension, else the name, by a small rule table,
/// not a content check.
public enum FileKind: CaseIterable, Sendable {
    case applications, documents, media, developer, system, other

    private static let extensions: [String: FileKind] = {
        var table: [String: FileKind] = [:]
        for ext in ["app", "appex", "dmg", "pkg", "framework", "plugin", "bundle"] { table[ext] = .applications }
        for ext in ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "txt", "rtf", "md",
                    "csv", "epub", "emlx", "mbox"] { table[ext] = .documents }
        for ext in ["jpg", "jpeg", "png", "heic", "gif", "tif", "tiff", "dng", "psd", "mov", "mp4", "m4v", "avi", "mkv",
                    "mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "photoslibrary", "musiclibrary", "tvlibrary",
                    "logicx", "band"] { table[ext] = .media }
        for ext in ["swift", "c", "h", "m", "cpp", "rs", "go", "py", "js", "jsx", "ts", "tsx", "cs", "java", "kt", "rb",
                    "php", "o", "a", "so", "dylib", "dll", "pdb", "jar", "class", "xcodeproj", "xcworkspace", "xcarchive",
                    "simruntime"] { table[ext] = .developer }
        return table
    }()

    private static let names: [String: FileKind] = [
        "Applications": .applications, "Containers": .applications, "Group Containers": .applications,
        "Application Support": .applications,
        "Documents": .documents, "Desktop": .documents, "Mail": .documents,
        "Pictures": .media, "Movies": .media, "Music": .media,
        "Developer": .developer, "node_modules": .developer, ".build": .developer, ".git": .developer,
        "DerivedData": .developer, "Docker.raw": .developer, ".docker": .developer, ".cargo": .developer,
        ".npm": .developer, "homebrew": .developer,
        "System": .system, "Library": .system, "Caches": .system, "Logs": .system, "private": .system, "usr": .system,
    ]

    /// `names` runs from the scanned root's first level down to the item; `largest` is a folder's largest item, that
    /// item's largest item, and so on. The first rule found wins: the item, then its largest items, then its folders.
    public static func of(_ names: [String], largest: [String] = []) -> FileKind {
        (names.suffix(1) + largest + names.dropLast().reversed()).lazy.compactMap(rule).first ?? .other
    }

    private static func rule(_ name: String) -> FileKind? {
        let ext = name.split(separator: ".", omittingEmptySubsequences: false).dropFirst().last.map { $0.lowercased() }
        return ext.flatMap { extensions[$0] } ?? names[name]
    }
}

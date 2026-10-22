// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ActivityMonitorX",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1"),
    ],
    targets: [
        .target(name: "CAMX", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),
        .target(name: "AMXCore", dependencies: [
            "CAMX",
            .product(name: "GRDB", package: "GRDB.swift"),
        ]),
        .executableTarget(name: "amxd", dependencies: ["AMXCore"]),
        .executableTarget(name: "amx", dependencies: ["AMXCore"]),
        .executableTarget(name: "ActivityMonitorX", dependencies: ["AMXCore"]),
        .testTarget(name: "AMXCoreTests", dependencies: ["AMXCore"], exclude: ["Fixtures"]),
    ],
    swiftLanguageModes: [.v6]
)

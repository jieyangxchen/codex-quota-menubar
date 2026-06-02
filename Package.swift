// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "codex-quota-menubar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexQuotaCore", targets: ["CodexQuotaCore"]),
        .executable(name: "codex-quota-menubar", targets: ["CodexQuotaMenubar"]),
        .executable(name: "codex-quota-core-tests", targets: ["CodexQuotaCoreTestsRunner"])
    ],
    targets: [
        .target(name: "CodexQuotaCore"),
        .executableTarget(name: "CodexQuotaMenubar", dependencies: ["CodexQuotaCore"]),
        .executableTarget(name: "CodexQuotaCoreTestsRunner", dependencies: ["CodexQuotaCore"])
    ]
)

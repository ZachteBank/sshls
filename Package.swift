// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SSHConfigManager",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SSHConfigKit"),
        .executableTarget(name: "SSHConfigManager", dependencies: ["SSHConfigKit"]),
        .executableTarget(name: "sshls", dependencies: ["SSHConfigKit"]),
        .executableTarget(name: "SSHConfigKitChecks", dependencies: ["SSHConfigKit"]),
    ]
)

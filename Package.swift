// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VPNGuard",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "guard-probe", targets: ["GuardProbe"])],
    targets: [
        .target(name: "GuardCore"),
        .executableTarget(name: "GuardProbe", dependencies: ["GuardCore"]),
        .testTarget(name: "GuardCoreTests", dependencies: ["GuardCore"]),
    ]
)


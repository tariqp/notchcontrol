// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "NotchControl",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "NotchControl", path: "Sources/NotchControl"),
        .executableTarget(name: "notchcontrol-bridge", path: "Sources/notchcontrol-bridge"),
    ],
    swiftLanguageVersions: [.v5]
)

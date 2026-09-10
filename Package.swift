// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Slant",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Slant",
            path: "Sources/Slant"
        )
    ]
)

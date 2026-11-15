// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Tonica",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Tonica",
            path: "Sources/Tonica"
        )
    ]
)

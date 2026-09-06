// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "davecal",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "davecal",
            path: "Sources/davecal"
        )
    ]
)

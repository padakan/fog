// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeStatusBorder",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ClaudeStatusBorder",
            path: "Sources/ClaudeStatusBorder"
        )
    ]
)

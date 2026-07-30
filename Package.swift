// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodexBarMonterey",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "CodexBarMonterey", targets: ["CodexBarMonterey"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4"),
    ],
    targets: [
        .executableTarget(
            name: "CodexBarMonterey",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/CodexBarMonterey"
        ),
    ],
    swiftLanguageModes: [.v5]
)

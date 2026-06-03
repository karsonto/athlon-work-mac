// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AthlonAgent",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.0")
    ],
    targets: [
        .executableTarget(
            name: "AthlonAgent",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "AthlonAgent",
            exclude: ["Info.plist"],
            resources: [
                .process("Assets.xcassets"),
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "AthlonAgentTests",
            dependencies: ["AthlonAgent"],
            path: "Tests"
        )
    ]
)

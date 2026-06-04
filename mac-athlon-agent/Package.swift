// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AthlonAgent",
    platforms: [
        .macOS(.v12)
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1")
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
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "AthlonAgentTests",
            dependencies: ["AthlonAgent"],
            path: "Tests"
        )
    ]
)

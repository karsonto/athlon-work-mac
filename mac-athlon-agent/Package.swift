// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AthlonAgent",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "AthlonAgent",
            path: "AthlonAgent",
            exclude: ["Info.plist"],
            resources: [
                .process("Assets.xcassets")
            ]
        )
    ]
)

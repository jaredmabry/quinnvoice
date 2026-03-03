// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "QuinnVoice",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "QuinnVoice", targets: ["QuinnVoice"])
    ],
    dependencies: [
        .package(url: "https://github.com/paradigms-of-intelligence/swift-gemini-api", branch: "main"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "QuinnVoice",
            dependencies: [
                .product(name: "swift-gemini-api", package: "swift-gemini-api"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "QuinnVoiceTests",
            dependencies: ["QuinnVoice"],
            path: "Tests/QuinnVoiceTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)

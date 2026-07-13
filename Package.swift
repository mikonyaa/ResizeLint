// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "ResizeLint",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "resizelint", targets: ["ResizeLintCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "603.0.2"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2"),
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
    ],
    targets: [
        .target(
            name: "ResizeLintCore",
            dependencies: [
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftParserDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                "Yams",
            ],
            swiftSettings: strictSwiftSettings
        ),
        .executableTarget(
            name: "ResizeLintCLI",
            dependencies: [
                "ResizeLintCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "ResizeLintCoreTests",
            dependencies: ["ResizeLintCore"],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "ResizeLintCLITests",
            dependencies: ["ResizeLintCLI", "ResizeLintCore"],
            swiftSettings: strictSwiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)

let strictSwiftSettings: [SwiftSetting] = [
    .unsafeFlags(["-warnings-as-errors"]),
]

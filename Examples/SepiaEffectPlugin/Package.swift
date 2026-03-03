// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SepiaEffectPlugin",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "SepiaEffectPlugin",
            type: .dynamic,
            targets: ["SepiaEffectPlugin"]
        ),
    ],
    dependencies: [
        // Reference the main SwiftEditor package for PluginKit protocols
        .package(path: "../.."),
    ],
    targets: [
        .target(
            name: "SepiaEffectPlugin",
            dependencies: [
                .product(name: "PluginKit", package: "SwiftEditor"),
                .product(name: "CoreMediaPlus", package: "SwiftEditor"),
            ],
            path: "Sources/SepiaEffectPlugin"
        ),
    ]
)

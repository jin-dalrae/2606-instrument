// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "MiniLabParticleDJ",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MiniLabParticleDJ", targets: ["MiniLabParticleDJ"])
    ],
    dependencies: [
        .package(url: "https://github.com/AudioKit/AudioKit.git", from: "5.7.0")
    ],
    targets: [
        .executableTarget(
            name: "MiniLabParticleDJ",
            dependencies: [
                .product(name: "AudioKit", package: "AudioKit")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MiniLabParticleDJTests",
            dependencies: ["MiniLabParticleDJ"]
        )
    ],
    swiftLanguageModes: [.v6]
)

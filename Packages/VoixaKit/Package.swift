// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoixaKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "VoixaKit", targets: ["VoixaKit"]),
        .library(name: "VoixaEngines", targets: ["VoixaEngines"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", .upToNextMinor(from: "1.1.1")),
    ],
    targets: [
        // Pure logic, no heavy dependencies.
        .target(name: "VoixaKit"),
        // Speech-to-text backends.
        .target(
            name: "VoixaEngines",
            dependencies: [
                "VoixaKit",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ]
        ),
        // Transcribes audio files; used for testing and accuracy evaluation.
        .executableTarget(
            name: "voixa-transcribe",
            dependencies: ["VoixaKit", "VoixaEngines"]
        ),
        .testTarget(name: "VoixaKitTests", dependencies: ["VoixaKit"]),
    ]
)

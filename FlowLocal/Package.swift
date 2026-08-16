// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlowLocal",
    platforms: [.macOS("26.0")],
    dependencies: [
        // Pinned after integration testing (spec §0.13).
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.1"),
        .package(url: "https://github.com/FluidInference/FluidAudio", from: "0.15.5"),
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "1.0.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.4"),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "FlowLocal",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            path: "Sources/FlowLocal"
        ),
        .testTarget(
            name: "FlowLocalTests",
            dependencies: ["FlowLocal"],
            path: "Tests/FlowLocalTests"
        ),
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "cmagic",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "CodemagicApiKit", targets: ["CodemagicApiKit"]),
        .executable(name: "cmagic", targets: ["cmagic"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.7.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.8.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "CodemagicApiKit",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
            ]
        ),
        .executableTarget(
            name: "cmagic",
            dependencies: [
                "CodemagicApiKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "CodemagicApiKitTests",
            dependencies: ["CodemagicApiKit"]
        ),
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SendspinKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "SendspinKit",
            targets: ["SendspinKit"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/alta/swift-opus.git", from: "0.0.2"),
        .package(url: "https://github.com/sbooth/flac-binary-xcframework.git", from: "0.1.0"),
        .package(url: "https://github.com/sbooth/ogg-binary-xcframework.git", from: "0.1.0")
    ],
    targets: [
        .target(
            name: "SendspinKit",
            dependencies: [
                .product(name: "Opus", package: "swift-opus"),
                .product(name: "FLAC", package: "flac-binary-xcframework"),
                .product(name: "ogg", package: "ogg-binary-xcframework")
            ]
        ),
        .testTarget(
            name: "SendspinKitTests",
            dependencies: ["SendspinKit"]
        )
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CLIPlayer",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "CLIPlayer",
            dependencies: [
                .product(name: "SendspinKit", package: "SendspinKit")
            ]
        ),
        .executableTarget(
            name: "AudioTest",
            dependencies: [
                .product(name: "SendspinKit", package: "SendspinKit")
            ]
        ),
        .executableTarget(
            name: "SimpleTest",
            dependencies: [
                .product(name: "SendspinKit", package: "SendspinKit")
            ]
        ),
        .executableTarget(
            name: "OpusTest",
            dependencies: [
                .product(name: "SendspinKit", package: "SendspinKit")
            ],
            path: "Sources/OpusTest"
        ),
        .executableTarget(
            name: "FLACTest",
            dependencies: [
                .product(name: "SendspinKit", package: "SendspinKit")
            ],
            path: "Sources/FLACTest"
        )
    ]
)

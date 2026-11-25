// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PiHoleKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "PiHoleKit", targets: ["PiHoleKit"])
    ],
    targets: [
        .target(
            name: "PiHoleKit",
            path: "Sources/PiHoleKit"
        ),
        .testTarget(
            name: "PiHoleKitTests",
            dependencies: ["PiHoleKit"],
            path: "Tests/PiHoleKitTests"
        )
    ]
)

// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "ProjectConfiguration",
    platforms: [.macOS(.v10_13)],
    products: [.library(name: "ProjectConfiguration", targets: ["ProjectConfiguration"])],
    targets: [
        .target(name: "ProjectConfiguration"),
        .testTarget(name: "ProjectConfigurationTests", dependencies: ["ProjectConfiguration"]),
    ]
)

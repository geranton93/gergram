// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "SpeechModelSupport",
    platforms: [.macOS(.v10_13)],
    products: [.library(name: "SpeechModelSupport", targets: ["SpeechModelSupport"])],
    targets: [
        .target(name: "SpeechModelSupport"),
        .testTarget(name: "SpeechModelSupportTests", dependencies: ["SpeechModelSupport"]),
    ]
)

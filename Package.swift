// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HabitakerAuth",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AuthCore", targets: ["AuthCore"])],
    targets: [
        .target(name: "AuthCore"),
        .testTarget(name: "AuthCoreTests", dependencies: ["AuthCore"])
    ]
)

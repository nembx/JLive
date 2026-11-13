// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JLiveCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "JLiveCore", targets: ["JLiveCore"])],
    targets: [
        .target(name: "JLiveCore", resources: [.process("Resources")]),
        .testTarget(name: "JLiveCoreTests", dependencies: ["JLiveCore"])
    ]
)

// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MacCtrlHTTP",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacCtrlHTTP", targets: ["MacCtrlHTTP"]),
        .library(name: "MacCtrlHTTPCore", targets: ["MacCtrlHTTPCore"]),
    ],
    targets: [
        .target(name: "MacCtrlHTTPCore"),
        .executableTarget(name: "MacCtrlHTTP", dependencies: ["MacCtrlHTTPCore"]),
        .testTarget(name: "MacCtrlHTTPCoreTests", dependencies: ["MacCtrlHTTPCore"]),
    ]
)

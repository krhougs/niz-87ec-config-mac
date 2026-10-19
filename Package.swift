// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "NIZConfig",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NIZConfig", targets: ["NIZConfig"]),
        .executable(name: "nizctl", targets: ["nizctl"]),
        .library(name: "NIZKit", targets: ["NIZKit"]),
    ],
    targets: [
        .target(name: "NIZKit", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "nizctl", dependencies: ["NIZKit"]),
        .executableTarget(name: "NIZConfig", dependencies: ["NIZKit"]),
        .testTarget(name: "NIZKitTests", dependencies: ["NIZKit"], resources: [.copy("Fixtures")]),
    ]
)

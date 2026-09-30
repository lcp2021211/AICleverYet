// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AICleverYet",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "AICleverYet", targets: ["AICleverYet"]), .executable(name: "RadarChecks", targets: ["RadarChecks"])],
    targets: [
        .target(name: "RadarCore"),
        .executableTarget(name: "AICleverYet", dependencies: ["RadarCore"]),
        .executableTarget(name: "RadarChecks", dependencies: ["RadarCore"], path: "Tests/RadarCoreTests",
                    resources: [.copy("Fixtures")])
    ]
)

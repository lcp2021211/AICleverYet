// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GPTIQ",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "GPTIQ", targets: ["GPTIQ"]), .executable(name: "RadarChecks", targets: ["RadarChecks"])],
    targets: [
        .target(name: "RadarCore"),
        .executableTarget(name: "GPTIQ", dependencies: ["RadarCore"]),
        .executableTarget(name: "RadarChecks", dependencies: ["RadarCore"], path: "Tests/RadarCoreTests",
                    resources: [.copy("Fixtures")])
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeystoneRules",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "RuleEngine", targets: ["RuleEngine"])
    ],
    targets: [
        .target(
            name: "InventorySupport",
            path: "Core/Inventory",
            exclude: ["Tests"]
        ),
        .target(
            name: "RuleEngine",
            path: "Core/Rules/Engine"
        ),
        .testTarget(
            name: "RuleEngineTests",
            dependencies: ["RuleEngine"],
            path: "Core/Rules/Tests"
        ),
        .testTarget(
            name: "InventorySupportTests",
            dependencies: ["InventorySupport"],
            path: "Core/Inventory/Tests"
        )
    ]
)

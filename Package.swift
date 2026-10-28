// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Freefield",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Freefield", targets: ["Freefield"]),
    ],
    targets: [
        .target(
            name: "FreefieldCore",
            swiftSettings: [.enableUpcomingFeature("InferIsolatedConformances")]
        ),
        .executableTarget(
            name: "Freefield",
            dependencies: ["FreefieldCore"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
        .executableTarget(
            name: "FreefieldSmoke",
            dependencies: ["FreefieldCore"]
        ),
    ]
)

// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CodexQuotaAtoll",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "codex-quota-atoll", targets: ["CodexQuotaAtoll"]),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .target(name: "CodexQuotaCore"),
        .executableTarget(
            name: "CodexQuotaAtoll",
            dependencies: [
                "CodexQuotaCore",
                .product(name: "AtollExtensionKit", package: "AtollExtensionKit"),
            ]
        ),
        .testTarget(name: "CodexQuotaCoreTests", dependencies: ["CodexQuotaCore"]),
    ]
)

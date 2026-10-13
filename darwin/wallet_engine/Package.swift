// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "wallet_engine",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(name: "wallet-engine", targets: ["wallet_engine"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .binaryTarget(
            name: "WalletEngineCore",
            path: "WalletEngineCore.xcframework"
        ),
        .target(
            name: "wallet_engine",
            dependencies: [
                "WalletEngineCore",
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)

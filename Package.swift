// swift-tools-version: 6.3
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    // https://github.com/apple/swift-evolution/blob/main/proposals/0335-existential-any.md
    .enableUpcomingFeature("ExistentialAny"),

    // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0444-member-import-visibility.md
    .enableUpcomingFeature("MemberImportVisibility"),

    // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md
    .enableUpcomingFeature("InternalImportsByDefault"),

    // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
    name: "swift-authentication-vapor",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "AuthenticationVapor",
            targets: ["AuthenticationVapor"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/swift-microservices/swift-authentication.git", from: "0.3.0"),
        .package(url: "https://github.com/apple/swift-service-context.git", from: "1.3.0"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.122.0"),
    ],
    targets: [
        .target(
            name: "AuthenticationVapor",
            dependencies: [
                .product(name: "Authentication", package: "swift-authentication"),
                .product(name: "ServiceContextModule", package: "swift-service-context"),
                .product(name: "Vapor", package: "vapor"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AuthenticationVaporTests",
            dependencies: [
                .target(name: "AuthenticationVapor"),
                .product(name: "Authentication", package: "swift-authentication"),
                .product(name: "ServiceContextModule", package: "swift-service-context"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "VaporTesting", package: "vapor"),
            ],
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)

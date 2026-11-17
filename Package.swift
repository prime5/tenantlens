// swift-tools-version:5.9
import PackageDescription

// SwiftPM is the fast inner loop (`swift test`); Bazel is the monorepo build of record.
// Both build the same sources -- keep the target lists in sync with the BUILD.bazel files.
let package = Package(
    name: "TenantLens",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ETLCore", targets: ["ETLCore"]),
        .executable(name: "tenantlens", targets: ["TenantLensCLI"]),
    ],
    targets: [
        .target(name: "ETLCore", path: "Sources/ETLCore", exclude: ["BUILD.bazel"]),
        .target(name: "DataGen", dependencies: ["ETLCore"], path: "Sources/DataGen", exclude: ["BUILD.bazel"]),
        .executableTarget(
            name: "TenantLensCLI",
            dependencies: ["ETLCore", "DataGen"],
            path: "Sources/TenantLensCLI",
            exclude: ["BUILD.bazel"]
        ),
        .testTarget(
            name: "ETLCoreTests",
            dependencies: ["ETLCore", "DataGen"],
            path: "Tests/ETLCoreTests",
            exclude: ["BUILD.bazel"]
        ),
    ]
)

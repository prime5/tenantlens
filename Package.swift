// swift-tools-version:5.9
import PackageDescription

// SwiftPM is the fast inner loop (`swift test`); Bazel is the monorepo build of record.
// Both build the same sources -- keep the target lists in sync with the BUILD.bazel files.
let package = Package(
    name: "TenantLens",
    platforms: [.macOS(.v14)],
    products: [
        // Library products so the Xcode app (Apps/Dashboard) can depend on them as a local package.
        .library(name: "ETLCore", targets: ["ETLCore"]),
        .library(name: "DataGen", targets: ["DataGen"]),
        .library(name: "WarehouseSQLite", targets: ["WarehouseSQLite"]),
        .library(name: "DashboardCore", targets: ["DashboardCore"]),
        .executable(name: "tenantlens", targets: ["TenantLensCLI"]),
    ],
    targets: [
        .target(name: "ETLCore", path: "Sources/ETLCore", exclude: ["BUILD.bazel"]),
        .target(name: "DataGen", dependencies: ["ETLCore"], path: "Sources/DataGen", exclude: ["BUILD.bazel"]),
        // macOS-only: imports the SDK's SQLite3 module (Linux would need a system-library target).
        .target(
            name: "WarehouseSQLite",
            dependencies: ["ETLCore"],
            path: "Sources/WarehouseSQLite",
            exclude: ["BUILD.bazel"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(name: "DashboardCore", dependencies: ["ETLCore"], path: "Sources/DashboardCore", exclude: ["BUILD.bazel"]),
        .executableTarget(
            name: "TenantLensCLI",
            dependencies: ["ETLCore", "DataGen", "WarehouseSQLite"],
            path: "Sources/TenantLensCLI",
            exclude: ["BUILD.bazel"]
        ),
        .testTarget(
            name: "ETLCoreTests",
            dependencies: ["ETLCore", "DataGen"],
            path: "Tests/ETLCoreTests",
            exclude: ["BUILD.bazel"]
        ),
        .testTarget(
            name: "WarehouseSQLiteTests",
            dependencies: ["ETLCore", "DataGen", "WarehouseSQLite"],
            path: "Tests/WarehouseSQLiteTests",
            exclude: ["BUILD.bazel"]
        ),
        .testTarget(
            name: "DashboardCoreTests",
            dependencies: ["DashboardCore", "DataGen", "ETLCore"],
            path: "Tests/DashboardCoreTests",
            exclude: ["BUILD.bazel"]
        ),
    ]
)

# TenantLens — design

A small multi-tenant BI stack in Swift: **ETL pipeline → tenant-scoped query layer → SwiftUI/Swift Charts dashboards**, built in a **Bazel monorepo**, with a test strategy that mirrors how an analytics product is actually verified.

## Why this project (the pitch in three lines)

1. It is the Birst story rebuilt natively: end-to-end quality for an analytics product (data in → numbers on screen), with Swift/XCUITest now current rather than 2017.
2. It exercises the Apple-platform testing stack end to end: XCTest/XCUITest, Swift, CI/CD, cloud-style APIs, and (stretch) validating a GenAI feature.
3. It closes the Bazel/monorepo gap by *using* Bazel, not reading about it.

## Birst → TenantLens map

| Birst-style concept | TenantLens analog | Where |
|---|---|---|
| Connect / extract from sources | `Extractor` (CSV now, JSON/SQLite later) | `ETLCore/CSV.swift` |
| Data refinery / processing | `Transform` stages: typecast, validate, dedupe, derive | `ETLCore/Transforms.swift` |
| Publish to the warehouse | `Sink` → `Warehouse` (in-memory, then SQLite) | `ETLCore/Warehouse.swift` |
| Space (tenant isolation) | `query(tenant:…)` has no unscoped variant | `Warehouse.query` |
| Measures & dimensions | `Measure` (count/sum/avg) + `groupBy` | `Warehouse.swift` |
| Dashboards | SwiftUI + Swift Charts app (Phase 3), Xcode project via XcodeGen | `Apps/Dashboard` |
| Mobile UI automation | XCUITest suite on the dashboard (Phase 4) | `Tests/DashboardUITests` |

## Test strategy: three layers, one oracle

The generator injects known defects (duplicates, negative quantities, impossible dates) on a deterministic schedule and returns a `GroundTruth`. Every layer is checked against that oracle, never against the system's own output.

1. **Pipeline / data** (Phase 1, done): counts, per-reason rejections, row conservation (`extracted == loaded + rejected`), revenue reconciliation per tenant.
2. **Query / semantics** (Phase 1 partial, Phase 2): tenant isolation, grouping totals add up, incremental loads don't double count, schema-drift cases.
3. **UI** (Phase 4): the number rendered in a chart's accessibility value equals the warehouse query for that tenant.

## Layout

```
MODULE.bazel  .bazelrc  .bazelversion  Package.swift
Sources/ETLCore        pure Swift, Foundation only (Linux-buildable)
Sources/DataGen        seeded generator + OrdersPipeline + ground truth
Sources/WarehouseSQLite SQLite3 C API wrapper + SQLiteWarehouse (macOS-only)
Sources/TenantLensCLI  run the pipeline, print report + rollups
Tests/ETLCoreTests     XCTest: CSV, pipeline oracle/golden, schema drift
Tests/WarehouseSQLiteTests XCTest: SQLite parity, injection guards, persistence, incremental loads
Tests/DashboardCoreTests XCTest: dashboard numbers vs ground truth, accessibility contract
Sources/DashboardCore  dashboard snapshot + run summary + AccessibilityID contract (UI-free, testable)
Apps/Dashboard         SwiftUI app; project.yml (XcodeGen) -> TenantLensDashboard.xcodeproj
Tests/DashboardUITests (Phase 4) XCUITest
```

SwiftPM is the fast inner loop (`swift test`); Bazel is the build of record (`bazel test //...`). Both read the same sources.

## Phases (each = one discrete deliverable and one commit; 30–45 min each)

| # | Deliverable | Commit message |
|---|---|---|
| 0+1 | Monorepo skeleton + ETL core + generator + tests (this drop) | `feat: Bazel/SwiftPM skeleton, ETL core, synthetic multi-tenant data, oracle tests` |
| 2 | SQLite warehouse (parity-tested against in-memory), upsert-based incremental loads + `load_runs` history, schema contract + reject-rate guard | `feat: sqlite warehouse, incremental loads, schema contract` |
| 3 | SwiftUI dashboard: tenant picker, revenue by region (bar), orders over time (line), run-report panel | `feat: SwiftUI dashboard with Swift Charts` |
| 4 | XCUITest suite + accessibility identifiers; UI-vs-warehouse reconciliation | `test: XCUITest reconciliation suite` |
| 5 | CI (GitHub Actions macOS runner + `bazel test //...`), flaky-test quarantine report | `ci: bazel test on macOS` |
| 6 (stretch) | Natural-language → `Query` translator, evaluated with a golden set (reuse llm-eval-harness) | `feat: NL query with eval harness` |

## Phase 2 decisions

- **SQLite via the SDK's C library**, no third-party packages (keeps Bazel dependency-free). Wrapped in `SQLiteDB`.
- **Money as REAL** (8-byte float). Tests compare with 1e-6 tolerance. Integer cents is the production-grade upgrade.
- **Correctness of incremental loads comes from upsert on `(tenant_id, order_id)`**, so re-runs are no-ops and corrections become updates. `load_runs` records each load.
- **Watermark deferred**: the generator's dates are not time-ordered, so a date high-water mark would flag most rows as "late". Revisit if a time-ordered source is added.
- **Schema drift**: header contract checked before any row; missing required column or reject rate > 50% refuses the batch; extra columns are ignored and reported.
- **Differential testing**: the in-memory warehouse is the reference; SQLite must return the same rows for every query shape (this pinned the SQL "aggregate over zero rows" difference via `HAVING COUNT(*) > 0`).

## Phase 3 decisions

- **The app is an Xcode project generated by XcodeGen** (`Apps/Dashboard/project.yml`), depending on the repo's Swift package as a local package. Apple-standard first; the app can move to Bazel (rules_apple) later. Bazel and SwiftPM still build and test all libraries, including `DashboardCore`.
- **`order_month` is derived in the pipeline**, so every dashboard series is exactly one tenant-scoped warehouse query: what Phase 4 reconciles against.
- **Test surface = chart marks + a table**: marks carry `accessibilityLabel`/`accessibilityValue` (VoiceOver); the table under each chart carries the stable identifiers from `AccessibilityID`.
- **Deterministic launch**: `-seed N` (default 42) and `-db path` (default `:memory:`) via the UserDefaults argument domain; XCUITest sets these.
- **Logic stays out of the app target**: `DashboardCore` builds the snapshot with plain functions; the app's `@Observable` model only holds state.
- **Known gap**: no schema migration. A database file created before `order_month` existed must be deleted.

## Honest notes

- Phase 0+1 verified on macOS with both `swift test` and `bazel test //...`. Phase 2 code was written without a local compile; first action is `swift test`.
- SwiftUI/Charts/XCUITest only build on macOS; `ETLCore` and its tests are the portable part.

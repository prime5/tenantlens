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
| Dashboards | SwiftUI + Swift Charts app (Phase 3) | `Apps/Dashboard` |
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
Sources/TenantLensCLI  run the pipeline, print report + rollups
Tests/ETLCoreTests     XCTest
Apps/Dashboard         (Phase 3) SwiftUI app, rules_apple macos_application
Tests/DashboardUITests (Phase 4) XCUITest
```

SwiftPM is the fast inner loop (`swift test`); Bazel is the build of record (`bazel test //...`). Both read the same sources.

## Phases (each = one discrete deliverable and one commit; 30–45 min each)

| # | Deliverable | Commit message |
|---|---|---|
| 0+1 | Monorepo skeleton + ETL core + generator + tests (this drop) | `feat: Bazel/SwiftPM skeleton, ETL core, synthetic multi-tenant data, oracle tests` |
| 2 | SQLite `Sink`, watermark-based incremental loads, idempotent re-runs, schema-drift tests | `feat: sqlite sink and incremental loads` |
| 3 | SwiftUI dashboard: tenant picker, revenue by region (bar), orders over time (line), run-report panel | `feat: SwiftUI dashboard with Swift Charts` |
| 4 | XCUITest suite + accessibility identifiers; UI-vs-warehouse reconciliation | `test: XCUITest reconciliation suite` |
| 5 | CI (GitHub Actions macOS runner + `bazel test //...`), flaky-test quarantine report | `ci: bazel test on macOS` |
| 6 (stretch) | Natural-language → `Query` translator, evaluated with a golden set (reuse llm-eval-harness) | `feat: NL query with eval harness` |

## Honest notes

- **Not compiled yet.** This drop was written without a Swift toolchain (the cloud sandbox cannot install one). First action on your Mac is `swift test`; expect a few small compiler fixes. Paste any errors back and they get fixed in the next session.
- **Bazel version pins** in `MODULE.bazel` are best guesses; bump if resolution fails.
- SwiftUI/Charts/XCUITest only build on macOS; `ETLCore` and its tests are the portable part.

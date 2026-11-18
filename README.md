# TenantLens

A small multi-tenant BI stack in Swift: **ETL pipeline → tenant-scoped warehouse → SwiftUI + Swift Charts dashboard**, with a test strategy built around one idea: every number is checked against an independent oracle, never against the system's own output.

## What's here

| Layer | What it does | Verified by |
|---|---|---|
| `ETLCore` | CSV extract, typecast / validate / dedupe / derive transforms, run report, schema contract, reject-rate guard | Row conservation (`extracted == loaded + rejected`), per-reason rejection counts, schema-drift cases |
| `DataGen` | Seeded generator that injects known defects (duplicates, negative quantities, impossible dates) and returns a `GroundTruth` oracle | Same seed → identical data; hand-derived golden totals |
| `WarehouseSQLite` | SQLite warehouse via the SDK's C API: upsert by primary key, load history, tenant-scoped queries only | Differential tests against an in-memory reference warehouse; SQL-injection guards; persistence across connections; idempotent re-runs and corrections |
| `DashboardCore` | Dashboard data (one warehouse query per series) and the accessibility-identifier contract | Dashboard numbers vs ground truth; pinned identifiers |
| `Apps/Dashboard` | SwiftUI + Swift Charts macOS app: tenant picker, revenue by region, orders by month, run report | XCUITest suite: every value on screen reconciled against an independent recomputation, per tenant |

## Run it

Requires macOS 14+ and Xcode.

```bash
swift test                                   # all library tests (SwiftPM)
swift run tenantlens /tmp/tl.sqlite          # run the pipeline; run twice to see an idempotent re-load

brew install bazelisk
bazel test //...                             # same libraries and tests, built with Bazel (bzlmod)

brew install xcodegen
cd Apps/Dashboard && xcodegen generate && open TenantLensDashboard.xcodeproj   # ⌘R runs the app, ⌘U runs the UI tests
```

The app takes `-seed N` (default 42) and `-db path` (default in-memory) as launch arguments, so a given seed always renders the same dashboard.

## Design

See [`docs/DESIGN.md`](docs/DESIGN.md) for the architecture, the per-phase decisions and tradeoffs, and known gaps.

## Status

| Phase | Deliverable | State |
|---|---|---|
| 0+1 | Monorepo skeleton, ETL core, synthetic data, oracle + golden tests | Done |
| 2 | SQLite warehouse, incremental loads, schema contract | Done |
| 3 | SwiftUI dashboard with Swift Charts | Done |
| 4 | XCUITest: UI values reconciled against the warehouse | Done |
| 4.5 | Memory: measure, fix, guard (XCTMemoryMetric, leak tests) | In progress |
| 5 | CI on GitHub Actions (macOS) | Planned |
| 6 | Natural-language → query, evaluated with a golden set | Stretch |

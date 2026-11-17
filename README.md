# TenantLens

Multi-tenant ETL + query layer + dashboards in Swift, built with Bazel. See `docs/DESIGN.md`.

```bash
swift test                                   # fast loop (SwiftPM)
swift run tenantlens                         # run the pipeline, print the report

bazelisk test //...                          # build of record (Bazel)
bazelisk run //Sources/TenantLensCLI:tenantlens
```

Requires macOS 14+, Xcode (for the Swift toolchain), and `brew install bazelisk` for Bazel.

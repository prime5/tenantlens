import Foundation
import ETLCore

/// Seeded PRNG so every run with the same seed produces byte-identical data.
/// (Swift's SystemRandomNumberGenerator is not seedable -- Python's random.Random(seed) is.)
public struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

public struct GenConfig {
    public var tenants: Int
    public var ordersPerTenant: Int
    public var seed: UInt64

    public init(tenants: Int = 3, ordersPerTenant: Int = 200, seed: UInt64 = 42) {
        self.tenants = tenants
        self.ordersPerTenant = ordersPerTenant
        self.seed = seed
    }
}

/// The test oracle: exactly what the generator injected, so the pipeline's output can be
/// checked against an independent expectation rather than against itself.
public struct GroundTruth {
    public var totalDataLines = 0
    public var duplicates = 0
    public var negativeQuantity = 0
    public var badDate = 0
    public var cleanOrders = 0
    public var revenueByTenant: [String: Double] = [:]
    public init() {}
}

public struct Generated {
    public let csv: String
    public let truth: GroundTruth
}

public enum Generator {
    public static let regions = ["NA", "EMEA", "APAC"]
    public static let products = ["Alpha", "Beta", "Gamma", "Delta"]
    public static let header = "order_id,tenant_id,order_date,region,product,quantity,unit_price"

    /// Defect schedule (deterministic, priority order):
    ///   i % 40 == 0 -> negative quantity     (rejected by `positive_quantity`)
    ///   i % 55 == 0 -> impossible date       (rejected by `typecast`)
    ///   i % 25 == 0 -> clean row emitted twice (second copy rejected by `dedupe`)
    public static func orders(_ config: GenConfig = GenConfig()) -> Generated {
        var rng = SplitMix64(seed: config.seed)
        var lines = [header]
        var truth = GroundTruth()

        for t in 1...config.tenants {
            let tenant = "T\(t)"
            for i in 1...config.ordersPerTenant {
                let quantity = Int.random(in: 1...10, using: &rng)
                let price = Double(Int.random(in: 500..<9500, using: &rng)) / 100.0
                let region = regions[Int.random(in: 0..<regions.count, using: &rng)]
                let product = products[Int.random(in: 0..<products.count, using: &rng)]

                var date = String(format: "2026-%02d-%02d", 1 + (i % 12), 1 + (i % 28))
                var qty = quantity
                var duplicate = false

                if i % 40 == 0 {
                    qty = -quantity
                    truth.negativeQuantity += 1
                } else if i % 55 == 0 {
                    date = "2026-13-45"
                    truth.badDate += 1
                } else {
                    truth.cleanOrders += 1
                    truth.revenueByTenant[tenant, default: 0] += Double(quantity) * price
                    if i % 25 == 0 {
                        duplicate = true
                        truth.duplicates += 1
                    }
                }

                let line = "\(tenant)-\(i),\(tenant),\(date),\(region),\(product),\(qty),\(price)"
                lines.append(line)
                truth.totalDataLines += 1
                if duplicate {
                    lines.append(line)
                    truth.totalDataLines += 1
                }
            }
        }
        return Generated(csv: lines.joined(separator: "\n") + "\n", truth: truth)
    }
}

/// The orders ETL: typecast -> validate -> dedupe -> derive revenue.
public enum OrdersPipeline {
    public static let schema = Schema([
        Column("order_id", .string),
        Column("tenant_id", .string),
        Column("order_date", .date),
        Column("region", .string),
        Column("product", .string),
        Column("quantity", .int),
        Column("unit_price", .double),
    ])

    public static func make(csv: String) -> Pipeline {
        Pipeline(
            extractor: CSVExtractor(text: csv),
            transforms: [
                TypeCast(schema),
                Validate(name: "positive_quantity", reason: "non_positive:quantity") { row in
                    (row["quantity"]?.int ?? 0) > 0
                },
                Dedupe(keys: ["order_id"]),
                Derive(column: "revenue") { row in
                    .double((row["quantity"]?.double ?? 0) * (row["unit_price"]?.double ?? 0))
                },
            ]
        )
    }
}

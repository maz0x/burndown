import Foundation

// Model pricing (current public list prices, USD per 1M input/output tokens). Cache derives from the
// input rate: write 5m = 1.25×, write 1h = 2×, read = 0.1×. Foundation-pure so the headless harness
// (run-pricing-tests.sh) can compile and test the real rate table + cost math with no Combine.

struct Price { let input, output: Double }

func priceFor(model: String) -> Price {
    let m = model.lowercased()
    if m.contains("opus") {
        // Opus 4.5 and later are $5/$25; the older ones (3, 4.0, 4.1) were $15/$75.
        //
        // These have to be matched against the ids that actually appear in the logs, which is what
        // the previous set did not do. "opus-4-0" was written for a model whose real id is
        // claude-opus-4-20250514: there is no "4-0" anywhere in it, so it never matched and every
        // Opus 4.0 token was priced at a third of its true cost. "opus-3" had the same defect, for
        // the same reason: the id is claude-3-opus-20240229, which reads "3-opus", not "opus-3".
        //
        // The dated form is matched by its year, NOT by a bare "opus-4" prefix, because that would
        // swallow opus-4-5 and opus-4-8 and charge them triple.
        if m.contains("opus-4-20") || m.contains("opus-4-1") || m.contains("3-opus") {
            return Price(input: 15, output: 75)
        }
        return Price(input: 5, output: 25)
    }
    if m.contains("fable")  { return Price(input: 10, output: 50) }
    if m.contains("sonnet") { return Price(input: 3, output: 15) }
    if m.contains("haiku")  { return Price(input: 1, output: 5) }
    return Price(input: 3, output: 15)
}

/// Estimated USD cost of one usage record: each token bucket priced at its model's rate, with cache
/// writes at 1.25× / 2× the input rate and cache reads at 0.1×.
func tokenCost(model: String, input: Int, output: Int, cache5m: Int, cache1h: Int, cacheRead: Int) -> Double {
    let p = priceFor(model: model)
    return Double(input) / 1_000_000 * p.input
         + Double(output) / 1_000_000 * p.output
         + Double(cache5m) / 1_000_000 * (p.input * 1.25)
         + Double(cache1h) / 1_000_000 * (p.input * 2.0)
         + Double(cacheRead) / 1_000_000 * (p.input * 0.1)
}

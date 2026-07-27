import Foundation

// Foundation-pure model-mix advisor (feature #7): a gentle nudge to conserve the tighter-capped
// model (Opus) when its weekly limit is running low, by routing routine work to Sonnet instead.
// Kept AppKit / Combine / SwiftUI free so the headless harness (run-modelmix-tests.sh) can compile
// and test the real advice logic with no UI. The app feeds one ModelHeadroom per model family
// (family name plus fraction of that family's weekly limit already used) and surfaces the message.

/// How much of one model family's weekly limit is already spent (0.0 = none, 1.0 = fully used).
struct ModelHeadroom {
    let family: String
    let fractionUsed: Double
}

/// The advisor's verdict: whether to nudge, which family is tightest, the plain-English message,
/// and which family to route routine work to (Sonnet when advising, else the tightest family).
struct ModelMixAdvice {
    let shouldAdvise: Bool
    let tightestFamily: String
    let message: String
    let recommendedFamily: String
}

/// Advise conserving Opus when it is the most-used family and has crossed adviseThreshold.
/// tightest = the headroom with the highest fractionUsed (ties broken by family ascending for
/// determinism). We only nudge when that tightest family is Opus, since Opus is the tighter-capped
/// model worth conserving; for any other tightest family we stay quiet. Empty input is safe:
/// shouldAdvise false, tightestFamily "", recommendedFamily "", empty message.
func modelMixAdvice(_ headrooms: [ModelHeadroom], adviseThreshold: Double = 0.75) -> ModelMixAdvice {
    guard let tightest = headrooms.max(by: { a, b in
        a.fractionUsed != b.fractionUsed ? a.fractionUsed < b.fractionUsed : a.family > b.family
    }) else {
        return ModelMixAdvice(shouldAdvise: false, tightestFamily: "", message: "", recommendedFamily: "")
    }

    let advise = tightest.fractionUsed >= adviseThreshold && tightest.family == "Opus"
    let recommended = advise ? "Sonnet" : tightest.family
    let percent = Int((tightest.fractionUsed * 100).rounded())
    let message = advise
        ? "You are at \(percent)% of your Opus weekly limit, shift routine work to Sonnet"
        : ""

    return ModelMixAdvice(
        shouldAdvise: advise,
        tightestFamily: tightest.family,
        message: message,
        recommendedFamily: recommended
    )
}

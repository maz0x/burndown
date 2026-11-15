import Foundation

// Foundation-pure model-mix advisor: a gentle nudge to conserve the tighter-capped
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

/// Advise conserving the tightest capped model when it has crossed adviseThreshold.
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

    // Sonnet is the one family that never prompts a nudge: it is the model routine work is sent
    // TO. Opus keeps its own sentence. Any other family here is a model the plan caps separately
    // (Fable, today), and running low on it is worth saying even though this file cannot know
    // which model is the cheaper stand-in, so it says "another model" rather than naming one.
    let advise = tightest.fractionUsed >= adviseThreshold && tightest.family != "Sonnet"
    let isOpus = tightest.family == "Opus"
    let recommended = advise ? (isOpus ? "Sonnet" : "") : tightest.family
    let percent = Int((tightest.fractionUsed * 100).rounded())
    let message = !advise ? ""
        : isOpus ? "You are at \(percent)% of your Opus weekly limit, shift routine work to Sonnet"
        : "You are at \(percent)% of your \(tightest.family) weekly limit, shift routine work to another model"

    return ModelMixAdvice(
        shouldAdvise: advise,
        tightestFamily: tightest.family,
        message: message,
        recommendedFamily: recommended
    )
}

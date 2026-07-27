import Foundation

// Tests for the Foundation-pure model-mix advisor (Sources/ModelMix.swift). ModelHeadroom and
// ModelMixAdvice are the real types from that file (compiled together by run-modelmix-tests.sh),
// so nothing is redeclared here. Same check()/failures/exit(1) convention as Tests/chartdata/main.swift.

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    print(cond ? "  ok   \(msg)" : "  FAIL \(msg)")
    if !cond { failures += 1 }
}

print("modelMixAdvice (advising, Opus tightest):")
let a1 = modelMixAdvice([
    ModelHeadroom(family: "Opus", fractionUsed: 0.78),
    ModelHeadroom(family: "Sonnet", fractionUsed: 0.40),
])
check(a1.shouldAdvise, "advises when Opus is tightest and over threshold")
check(a1.tightestFamily == "Opus", "tightest family is Opus")
check(a1.recommendedFamily == "Sonnet", "recommends Sonnet when advising")
check(a1.message == "You are at 78% of your Opus weekly limit, shift routine work to Sonnet",
      "message reports the rounded Opus percent and the Sonnet nudge")
check(!a1.message.contains("\u{2014}"), "message has no em-dash")

print("modelMixAdvice (boundary at the threshold):")
let a2 = modelMixAdvice([ModelHeadroom(family: "Opus", fractionUsed: 0.75)])
check(a2.shouldAdvise, "advises exactly at the default 0.75 threshold (>= is inclusive)")
check(a2.message == "You are at 75% of your Opus weekly limit, shift routine work to Sonnet",
      "boundary message reports 75%")

let a3 = modelMixAdvice([ModelHeadroom(family: "Opus", fractionUsed: 0.7499)])
check(!a3.shouldAdvise, "does not advise just below the threshold")
check(a3.tightestFamily == "Opus", "still reports Opus as tightest when not advising")
check(a3.recommendedFamily == "Opus", "recommends the tightest family itself when not advising")
check(a3.message == "", "empty message when not advising")

print("modelMixAdvice (Opus not tightest):")
let a4 = modelMixAdvice([
    ModelHeadroom(family: "Opus", fractionUsed: 0.80),
    ModelHeadroom(family: "Sonnet", fractionUsed: 0.95),
])
check(!a4.shouldAdvise, "stays quiet when Sonnet (not Opus) is the tightest family")
check(a4.tightestFamily == "Sonnet", "tightest family is Sonnet")
check(a4.recommendedFamily == "Sonnet", "recommends the tightest family when not advising")
check(a4.message == "", "empty message when the tightest family is not Opus")

print("modelMixAdvice (custom threshold):")
let a5 = modelMixAdvice([ModelHeadroom(family: "Opus", fractionUsed: 0.60)], adviseThreshold: 0.50)
check(a5.shouldAdvise, "honors a custom lower threshold")
check(a5.message == "You are at 60% of your Opus weekly limit, shift routine work to Sonnet",
      "custom-threshold message reports 60%")

print("modelMixAdvice (tie-break determinism):")
let a6 = modelMixAdvice([
    ModelHeadroom(family: "Opus", fractionUsed: 0.90),
    ModelHeadroom(family: "Sonnet", fractionUsed: 0.90),
])
check(a6.tightestFamily == "Opus", "ties on fractionUsed break to the lower family name (Opus < Sonnet)")
check(a6.shouldAdvise, "advises since the tie resolves to Opus over threshold")

print("modelMixAdvice (full-cap rounding):")
let a7 = modelMixAdvice([ModelHeadroom(family: "Opus", fractionUsed: 1.0)])
check(a7.message == "You are at 100% of your Opus weekly limit, shift routine work to Sonnet",
      "fractionUsed 1.0 renders as 100%")

print("modelMixAdvice (empty input):")
let a8 = modelMixAdvice([])
check(!a8.shouldAdvise, "empty input -> does not advise")
check(a8.tightestFamily == "", "empty input -> tightestFamily is empty")
check(a8.recommendedFamily == "", "empty input -> recommendedFamily is empty")
check(a8.message == "", "empty input -> empty message")

print(failures == 0 ? "\nALL MODELMIX TESTS PASSED" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)

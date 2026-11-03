import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAILED: \(message)\n", stderr); exit(1) }
}

@main struct Tests {
    static func main() {
        let labelled = QuizResult.parse(#"{"answers":[{"question":"1","label":"B","answer":"The planet Mars","why":"Example explanation","confidence":"high"}],"note":""}"#)
        check(labelled.hoverSummary == "Answer: B", "visible label")
        check(labelled.detailText.contains("B — The planet Mars"), "option detail")

        let unlabelled = QuizResult.parse(#"{"answers":[{"question":"1","label":"","answer":"Photosynthesis converts light energy into chemical energy.","why":"","confidence":"medium"}],"note":""}"#)
        check(unlabelled.hoverSummary == "Answer: Photosynthesis converts light energy into chemical energy.", "full answer without label")

        let multiple = QuizResult.parse(#"{"answers":[{"question":"1","label":"3","answer":"Third option","why":"","confidence":"high"},{"question":"2","label":"D","answer":"Fourth option","why":"","confidence":"medium"}],"note":""}"#)
        check(multiple.hoverSummary == "1: 3\n2: D", "multiple questions")

        let unreadable = QuizResult.parse(#"{"answers":[],"note":"Unreadable image"}"#)
        check(unreadable.hoverSummary == "Unreadable image", "message when there are no questions")

        let fallback = QuizResult.parse("The answer is water.")
        check(fallback.hoverSummary == "Answer: The answer is water.", "text fallback")
        print("Formatting and parsing tests: OK (5 scenarios).")
    }
}

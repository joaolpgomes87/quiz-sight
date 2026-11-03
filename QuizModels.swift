import Foundation

// Data independent of the macOS interface, also testable on Linux.
struct QuizAnswer: Equatable {
    let question: String
    let label: String        // Letter or number only when explicitly shown in the image.
    let answer: String       // Option or answer text, required even without a label.
    let why: String
    let confidence: String

    var shortAnswer: String {
        let value = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? (answer.isEmpty ? "?" : answer) : value
    }
}

struct QuizResult {
    let answers: [QuizAnswer]
    let note: String

    var hoverSummary: String {
        if answers.isEmpty { return note.isEmpty ? "No questions identified." : note }
        if answers.count == 1 { return "Answer: \(answers[0].shortAnswer)" }
        return answers.map { "\($0.question): \($0.shortAnswer)" }.joined(separator: "\n")
    }

    var detailText: String {
        if answers.isEmpty { return note.isEmpty ? "Select the entire question, including the options." : note }
        let lines = answers.map { item -> String in
            let content = item.label.isEmpty ? item.answer :
                (item.answer.isEmpty ? item.label : "\(item.label) — \(item.answer)")
            let explanation = item.why.isEmpty ? "" : "\n\(item.why)"
            let confidence = item.confidence.isEmpty ? "" : "\nConfidence: \(item.confidence)"
            return "Question \(item.question)\nAnswer: \(content)\(explanation)\(confidence)"
        }
        let joined = lines.joined(separator: "\n\n")
        return note.isEmpty ? joined : "\(joined)\n\nNote: \(note)"
    }

    static func parse(_ raw: String) -> QuizResult {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Preserve the response text if the model does not return JSON.
            let fallback = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return QuizResult(answers: fallback.isEmpty ? [] : [QuizAnswer(
                question: "1", label: "", answer: fallback, why: "", confidence: ""
            )], note: "")
        }
        let items = object["answers"] as? [[String: Any]] ?? []
        let answers = items.enumerated().map { index, item in
            QuizAnswer(
                question: value(item["question"], fallback: "\(index + 1)"),
                label: value(item["label"]),
                answer: value(item["answer"]),
                why: value(item["why"]),
                confidence: value(item["confidence"])
            )
        }
        return QuizResult(answers: answers, note: value(object["note"]))
    }

    private static func value(_ thing: Any?, fallback: String = "") -> String {
        if let string = thing as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let number = thing as? NSNumber { return number.stringValue }
        return fallback
    }
}

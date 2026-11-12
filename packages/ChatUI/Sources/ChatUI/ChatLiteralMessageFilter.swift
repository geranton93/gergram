import Foundation
import InAppSettings

struct ChatLiteralMessageFilter {
    let text: String
    let pattern: String
    let sourceText: String

    init?(selectedText: String, originalText: String) {
        let maximumPatternLength = LocalMessageFilterEvaluation.maximumPatternLength
        let maximumInputLength = LocalMessageFilterEvaluation.maximumInputLength
        guard selectedText.utf16.prefix(maximumPatternLength + 1).count <= maximumPatternLength,
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              originalText.utf16.prefix(maximumInputLength + 1).count <= maximumInputLength,
              originalText.range(of: selectedText, options: .literal) != nil else { return nil }
        let pattern = NSRegularExpression.escapedPattern(for: selectedText)
        guard pattern.utf16.prefix(maximumPatternLength + 1).count <= maximumPatternLength else { return nil }
        self.text = selectedText
        self.pattern = pattern
        self.sourceText = originalText
    }
}

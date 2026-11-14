import Foundation

enum ChatIndicatorCustomText {
    static let maximumLength = 16
    static let maximumUTF16Length = 48

    static func validated(_ value: String) -> String? {
        guard value.utf16.prefix(maximumUTF16Length + 1).count <= maximumUTF16Length else { return nil }
        let containsForbiddenScalar = value.unicodeScalars.contains { scalar in
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator:
                return true
            case .format:
                return scalar.value != 0x200C && scalar.value != 0x200D
                    && !(0xE0020 ... 0xE007F).contains(scalar.value)
            default:
                return false
            }
        }
        guard !containsForbiddenScalar else { return nil }
        let text = value.trimmingCharacters(in: .whitespaces)
        guard text.count <= maximumLength,
              text.isEmpty || text.unicodeScalars.contains(where: { !$0.properties.isDefaultIgnorableCodePoint }) else { return nil }
        return text
    }
}

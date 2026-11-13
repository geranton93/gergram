import Foundation

enum ChatZalgoTextFilter {
    static func presentation(for source: NSAttributedString) -> NSAttributedString? {
        guard let filtered = filteredText(source.string) else {
            return nil
        }
        let result = NSMutableAttributedString(string: filtered)
        source.enumerateAttributes(in: NSRange(location: 0, length: source.length), options: []) { attributes, range, _ in
            result.setAttributes(attributes, range: range)
        }
        return NSAttributedString(attributedString: result)
    }

    static func displayName(_ name: String, enabled: Bool) -> String {
        guard enabled else { return name }
        return filteredText(name) ?? name
    }

    private static func filteredText(_ text: String) -> String? {
        let scalars = text.unicodeScalars
        var result = String()
        var copiedEnd = scalars.startIndex
        var markStart = scalars.startIndex
        var markCount = 0
        var markUTF16Length = 0

        func replace(from start: String.Index, to end: String.Index, length: Int) {
            result.unicodeScalars.append(contentsOf: scalars[copiedEnd..<start])
            result.append(String(repeating: "\u{2060}", count: length))
            copiedEnd = end
        }

        func finishMarkRun(at end: String.Index) {
            if markCount >= 3 {
                replace(from: markStart, to: end, length: markUTF16Length)
            }
            markCount = 0
            markUTF16Length = 0
        }

        var index = scalars.startIndex
        while index < scalars.endIndex {
            let scalar = scalars[index]
            let next = scalars.index(after: index)
            if scalar.properties.generalCategory == .nonspacingMark {
                if markCount == 0 {
                    markStart = index
                }
                markCount += 1
                markUTF16Length += scalar.value > 0xFFFF ? 2 : 1
            } else {
                if markCount > 0 {
                    finishMarkRun(at: index)
                }
                switch scalar.value {
                case 0x061C, 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069:
                    replace(from: index, to: next, length: 1)
                default:
                    break
                }
            }
            index = next
        }
        finishMarkRun(at: scalars.endIndex)
        guard copiedEnd != scalars.startIndex else {
            return nil
        }
        result.unicodeScalars.append(contentsOf: scalars[copiedEnd...])
        return result
    }
}

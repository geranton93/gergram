import Foundation

struct PluginAttachmentMetadata: Equatable {
    enum ReadError: Error, Equatable {
        case unavailable
        case tooLarge
        case invalid
    }

    static let maximumFileSize = 512 * 1024

    let identifier: String
    let name: String
    let author: String?
    let version: String
    let minimumVersion: String?
    let requirements: [String]
    let icon: String?
    let description: String?

    static func matchesFileName(_ name: String?) -> Bool {
        return name?.lowercased().hasSuffix(".plugin") == true
    }

    static func read(from url: URL) -> Result<Self, ReadError> {
        guard url.isFileURL,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink == false else { return .failure(.unavailable) }
        if let size = values.fileSize, size > maximumFileSize {
            return .failure(.tooLarge)
        }
        guard let stream = InputStream(url: url) else { return .failure(.unavailable) }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while data.count <= maximumFileSize {
            let count = stream.read(&buffer, maxLength: min(buffer.count, maximumFileSize + 1 - data.count))
            if count < 0 { return .failure(.unavailable) }
            if count == 0 { return parse(data) }
            data.append(contentsOf: buffer.prefix(count))
        }
        return .failure(.tooLarge)
    }

    static func parse(_ data: Data) -> Result<Self, ReadError> {
        guard data.count <= maximumFileSize else { return .failure(.tooLarge) }
        guard !data.contains(0), let source = String(data: data, encoding: .utf8) else { return .failure(.invalid) }
        var scanner = Scanner(source)
        let fields = scanner.fields()

        guard let identifier = fields[.identifier], (2 ... 32).contains(identifier.utf8.count),
              let first = identifier.utf8.first, isASCIILetter(first),
              identifier.utf8.dropFirst().allSatisfy({ isASCIILetter($0) || (48 ... 57).contains($0) || $0 == 45 || $0 == 95 }),
              let name = displayText(fields[.name], limit: 100) else { return .failure(.invalid) }

        return .success(Self(
            identifier: identifier,
            name: name,
            author: displayText(fields[.author], limit: 200),
            version: displayText(fields[.version], limit: 32) ?? "1.0",
            minimumVersion: displayText(fields[.minimumVersion], limit: 64),
            requirements: displayText(fields[.requirements], limit: 1024)?.split(separator: ",").compactMap {
                displayText(String($0), limit: 200)
            } ?? [],
            icon: displayText(fields[.icon], limit: 256),
            description: displayText(fields[.description], limit: 8000)
        ))
    }

    private static func isASCIILetter(_ byte: UInt8) -> Bool {
        return (65 ... 90).contains(byte) || (97 ... 122).contains(byte)
    }

    private static func displayText(_ value: String?, limit: Int) -> String? {
        guard let value = value else { return nil }
        let visible = value.unicodeScalars.filter { $0 == "\n" || $0 == "\t" || !CharacterSet.controlCharacters.contains($0) }
        let trimmed = String(String.UnicodeScalarView(visible)).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.unicodeScalars.prefix(limit))
    }

    private enum Field: String {
        case identifier = "__id__"
        case name = "__name__"
        case author = "__author__"
        case version = "__version__"
        case minimumVersion = "__min_version__"
        case requirements = "__requirements__"
        case icon = "__icon__"
        case description = "__description__"
    }

    private struct Scanner {
        private let source: [Unicode.Scalar]
        private var offset = 0

        init(_ source: String) {
            self.source = Array(source.unicodeScalars)
            if current == "\u{feff}" { offset += 1 }
        }

        mutating func fields() -> [Field: String] {
            var result: [Field: String] = [:]
            var atLineStart = true
            var depth = 0
            while let scalar = current {
                if atLineStart, depth == 0, scalar == "_" {
                    var assignment = self
                    if let (field, value) = assignment.readAssignment() {
                        if result[field] == nil { result[field] = value }
                        self = assignment
                        atLineStart = false
                        continue
                    }
                }

                atLineStart = isLineBreak(scalar)
                switch scalar {
                case "#":
                    skipComment()
                case "\"", "'":
                    _ = readString()
                case "(", "[", "{":
                    depth += 1
                    offset += 1
                case ")", "]", "}":
                    depth = max(0, depth - 1)
                    offset += 1
                case "\\":
                    offset += 1
                    if current == "\r" { offset += 1 }
                    if current == "\n" { offset += 1 }
                default:
                    offset += 1
                }
            }
            return result
        }

        private mutating func readAssignment() -> (Field, String)? {
            let start = offset
            while let scalar = current, scalar == "_" || (97 ... 122).contains(scalar.value) {
                offset += 1
            }
            let name = String(String.UnicodeScalarView(source[start ..< offset]))
            guard let field = Field(rawValue: name) else { return nil }
            skipWhitespace(multiline: false)
            guard current == "=" else { return nil }
            offset += 1
            skipWhitespace(multiline: false)

            let grouped = current == "("
            if grouped {
                offset += 1
                skipWhitespace(multiline: true)
            }
            guard var value = readString() else { return nil }
            skipWhitespace(multiline: grouped)
            while current == "\"" || current == "'" {
                guard let part = readString() else { return nil }
                value += part
                skipWhitespace(multiline: grouped)
            }
            if grouped {
                guard current == ")" else { return nil }
                offset += 1
                skipWhitespace(multiline: false)
            }
            if let scalar = current, scalar != "#", !isLineBreak(scalar) { return nil }
            return (field, value)
        }

        private mutating func readString() -> String? {
            guard let quote = current, quote == "'" || quote == "\"" else { return nil }
            let triple = scalar(at: offset + 1) == quote && scalar(at: offset + 2) == quote
            offset += triple ? 3 : 1

            var text = String.UnicodeScalarView()
            while let scalar = current {
                if scalar == quote, !triple || (self.scalar(at: offset + 1) == quote && self.scalar(at: offset + 2) == quote) {
                    offset += triple ? 3 : 1
                    return String(text)
                }
                if !triple, isLineBreak(scalar) { return nil }
                offset += 1
                if scalar == "\\", let escaped = current {
                    offset += 1
                    switch escaped {
                    case "n": text.append("\n")
                    case "t": text.append("\t")
                    case "\"", "'", "\\": text.append(escaped)
                    case "\n": break
                    case "\r":
                        if current == "\n" { offset += 1 }
                    default:
                        text.append(scalar)
                        text.append(escaped)
                    }
                } else if scalar == "\r" {
                    if current == "\n" { offset += 1 }
                    text.append("\n")
                } else {
                    text.append(scalar)
                }
            }
            return nil
        }

        private mutating func skipWhitespace(multiline: Bool) {
            while let scalar = current {
                if scalar == " " || scalar == "\t" || (multiline && isLineBreak(scalar)) {
                    offset += 1
                } else if multiline, scalar == "#" {
                    skipComment()
                } else {
                    break
                }
            }
        }

        private mutating func skipComment() {
            while let scalar = current, !isLineBreak(scalar) { offset += 1 }
        }

        private func isLineBreak(_ scalar: Unicode.Scalar) -> Bool {
            return scalar == "\r" || scalar == "\n"
        }

        private var current: Unicode.Scalar? {
            return scalar(at: offset)
        }

        private func scalar(at offset: Int) -> Unicode.Scalar? {
            return offset < source.count ? source[offset] : nil
        }
    }
}

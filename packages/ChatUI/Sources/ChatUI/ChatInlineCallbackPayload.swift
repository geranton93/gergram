import Foundation

enum ChatInlineCallbackPayload: Equatable {
    case text(String)
    case base64(String)

    init(data: Data) {
        if let text = String(data: data, encoding: .utf8),
           !text.unicodeScalars.contains(where: {
               CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\r" && $0 != "\t"
           }) {
            self = .text(text)
        } else {
            self = .base64(data.base64EncodedString())
        }
    }
}

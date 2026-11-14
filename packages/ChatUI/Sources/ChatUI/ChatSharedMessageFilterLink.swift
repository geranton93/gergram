import Foundation
import InAppSettings

final class ChatSharedMessageFilterLink: NSObject {
    let rawValue: String

    init?(messageText: String, displayedText: String) {
        guard LocalMessageFilterTransfer.recognizesSharedRulesLink(messageText),
              messageText.utf8.elementsEqual(displayedText.utf8) else { return nil }
        self.rawValue = messageText
        super.init()
    }
}

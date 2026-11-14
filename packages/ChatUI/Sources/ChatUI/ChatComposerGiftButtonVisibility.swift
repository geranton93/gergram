import Postbox
import TelegramCore
import TelegramUtils

extension ChatPresentationInterfaceState {
    func showsComposerGiftButton(hidesGiftButton: Bool, accountPeerId: PeerId) -> Bool {
        guard hasGift, effectiveInput.inputText.isEmpty else { return false }
        guard hidesGiftButton, case .history = chatMode,
              !searchMode.inSearch, !isNotAccessible,
              let user = peer as? TelegramUser, user.id == chatLocation.peerId,
              user.id != accountPeerId, !user.isBot, !user.isDeleted,
              let data = cachedData as? CachedUserData, data.disallowedGifts != .All else { return true }
        return false
    }
}

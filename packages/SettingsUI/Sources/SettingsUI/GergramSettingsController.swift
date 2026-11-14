import TelegramContext
import TelegramLinks
import TGUIKit

public func gergramSettingsController<Context: AccountContextProtocol>(_ route: GergramSettingsRoute, context: Context) -> ViewController? {
    switch route {
    case .messageContextMenu:
        return messageContextMenuSettingsController()
    case .transcriptionLanguage:
        return receivedAudioTranscriptionLanguageController()
    case .filterZalgoText:
        let controller = GeneralSettingsViewController(context)
        controller.focusOnZalgoFilter()
        return controller
    case .miniAppWindowSize:
        return miniAppWindowSizeSettingsController()
    case .hideChatListStories:
        let controller = GeneralSettingsViewController(context)
        controller.focusOnHideChatListStories()
        return controller
    case .hideProfileStories:
        let controller = GeneralSettingsViewController(context)
        controller.focusOnHideProfileStories()
        return controller
    case .channelBottomAction:
        let controller = GeneralSettingsViewController(context)
        controller.focusOnChannelBottomAction()
        return controller
    case .sendWithoutSound:
        let controller = GeneralSettingsViewController(context)
        controller.focusOnSendWithoutSound()
        return controller
    case .messageBubbleCorners:
        return AppAppearanceViewController(context: context, focusOnItemTag: .messageBubbleRadius)
    case .avatarCorners:
        return AppAppearanceViewController(context: context, focusOnItemTag: .avatarRadius)
    case .editedMessageLabel:
        return AppAppearanceViewController(context: context, focusOnItemTag: .editedIndicatorText)
    case .locallyHiddenSenders:
        guard !context.isFrozen else { return nil }
        return localShadowBannedSendersController(context: context)
    case .messageFilters:
        guard !context.isFrozen else { return nil }
        return localMessageFiltersController(context: context)
    case .localMessageArchive:
        guard context.isCurrent, !context.isFrozen else { return nil }
        return localMessageArchiveController(context: context)
    }
}

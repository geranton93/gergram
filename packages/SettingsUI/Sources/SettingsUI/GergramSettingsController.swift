import TelegramContext
import TelegramLinks
import TGUIKit

public func gergramSettingsController(_ route: GergramSettingsRoute, context: any AccountContextProtocol) -> ViewController? {
    switch route {
    case .messageContextMenu:
        return messageContextMenuSettingsController()
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

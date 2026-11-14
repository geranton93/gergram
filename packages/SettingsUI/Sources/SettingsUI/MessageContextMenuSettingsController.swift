import AlertsUI
import GeneralRows
import InAppSettings
import InputDataUI
import LocalAnimations
import SwiftSignalKit
import TelegramTheme
import TGUIKit

private let preferences = MessageContextMenuPreferences()
private let actions = MessageContextMenuPreferences.Action.allCases
private let visibilityChoices = ValuePromise(currentChoices(), ignoreRepeated: true)

private func currentChoices() -> [MessageContextMenuPreferences.Visibility] {
    actions.map { preferences.visibility(for: $0) }
}

private func visibilityTitle(_ visibility: MessageContextMenuPreferences.Visibility) -> String {
    localizedString("Gergram.Chat.MenuSettings.\(visibility.rawValue)")
}

public func messageContextMenuSettingsController() -> InputDataController {
    let requestReset = MetaDisposable()
    let resetRequests = ValuePipe<Void>()
    let signal = visibilityChoices.get() |> deliverOnPrepareQueue |> map { choices in
        let sectionId: Int32 = 1
        var entries: [InputDataEntry] = [.sectionId(0, type: .normal)]

        for (index, action) in actions.enumerated() {
            let selected = choices[index]
            let options = MessageContextMenuPreferences.Visibility.allCases.map { visibility in
                ContextMenuItem(visibilityTitle(visibility), handler: {
                    preferences.setVisibility(visibility, for: action)
                    visibilityChoices.set(currentChoices())
                }, itemImage: selected == visibility ? MenuAnimation.menu_check_selected.value : nil)
            }
            let title = action == .messageDetails ? localizedString("Gergram.Chat.MessageDetails") : localizedString("Gergram.Chat.MenuSettings.\(action.rawValue)")
            entries.append(.general(sectionId: sectionId, index: Int32(index), value: .none, error: nil,
                                    identifier: InputDataIdentifier(action.rawValue),
                                    data: .init(name: title, color: theme.colors.text,
                                                type: .contextSelector(visibilityTitle(selected), options),
                                                viewType: bestGeneralViewType(actions, for: index))))
        }

        entries.append(.desc(sectionId: sectionId, index: Int32(actions.count),
                             text: .plain(localizedString("Gergram.Chat.MenuSettings.Hint")),
                             data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        entries.append(.sectionId(sectionId, type: .normal))
        entries.append(.general(sectionId: sectionId + 1, index: 0, value: .none, error: nil,
                                identifier: InputDataIdentifier("reset-visibility"),
                                data: .init(name: localizedString("Gergram.Chat.MenuSettings.Reset"), color: theme.colors.redUI,
                                            viewType: .singleItem, action: { resetRequests.putNext(()) })))
        return InputDataSignalValue(entries: entries)
    }

    let controller = InputDataController(dataSignal: signal, title: localizedString("Gergram.Chat.MenuSettings"), hasDone: false)
    requestReset.set((resetRequests.signal() |> deliverOnMainQueue).start(next: { [weak controller] _ in
        guard let controller, let window = controller.window else { return }
        let title = localizedString("Gergram.Chat.MenuSettings.Reset")
        verifyAlert_button(for: window, header: title, information: localizedString("Gergram.Chat.MenuSettings.ResetDescription"), ok: title, successHandler: { [weak controller] _ in
            guard controller != nil else { return }
            preferences.resetVisibility()
            visibilityChoices.set(currentChoices())
        })
    }))
    controller.onDeinit = { requestReset.dispose() }
    return controller
}

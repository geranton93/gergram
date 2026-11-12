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

func messageContextMenuSettingsController() -> InputDataController {
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
        return InputDataSignalValue(entries: entries)
    }

    return InputDataController(dataSignal: signal, title: localizedString("Gergram.Chat.MenuSettings"), hasDone: false)
}

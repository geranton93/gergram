import GeneralRows
import InAppSettings
import InputDataUI
import SwiftSignalKit
import TelegramTheme
import TGUIKit

func miniAppWindowSizeSettingsController() -> InputDataController {
    let preferences = MiniAppWindowSizePreferences()
    let dimensions = MiniAppWindowSizePreferences.Dimension.allCases
    let state = ValuePromise(Set(dimensions.filter(preferences.isEnlarged)), ignoreRepeated: true)

    let signal = state.get() |> deliverOnPrepareQueue |> map { enlarged in
        let sectionId: Int32 = 1
        var entries: [InputDataEntry] = [.sectionId(0, type: .normal)]
        for (index, dimension) in dimensions.enumerated() {
            let title = localizedString(dimension == .width ? "Gergram.MiniApp.WindowWider" : "Gergram.MiniApp.WindowTaller")
            let data = InputDataGeneralData(name: title, color: theme.colors.text,
                                            type: .switchable(enlarged.contains(dimension)),
                                            viewType: bestGeneralViewType(dimensions, for: index), action: {
                preferences.setEnlarged(!preferences.isEnlarged(dimension), for: dimension)
                state.set(Set(dimensions.filter(preferences.isEnlarged)))
            })
            entries.append(.general(sectionId: sectionId, index: Int32(index), value: .none, error: nil,
                                    identifier: InputDataIdentifier(dimension.rawValue), data: data))
        }
        entries.append(.desc(sectionId: sectionId, index: Int32(dimensions.count),
                             text: .plain(localizedString("Gergram.MiniApp.WindowSizeHint")),
                             data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        return InputDataSignalValue(entries: entries)
    }
    return InputDataController(dataSignal: signal, title: localizedString("Gergram.MiniApp.WindowSize"), hasDone: false)
}

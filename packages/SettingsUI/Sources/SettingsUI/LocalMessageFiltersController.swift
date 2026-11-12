import AlertsUI
import Foundation
import GeneralRows
import InAppSettings
import InputDataUI
import Localization
import Postbox
import SelectPeersUI
import SwiftSignalKit
import TelegramContext
import TelegramCore
import TelegramTheme
import TelegramUtils
import TGUIKit

private let patternId = InputDataIdentifier("pattern")

private func localMessageFilterEditor(context: any AccountContextProtocol, chatId: PeerId?, existing: LocalMessageFilterRule?) -> InputDataController {
    let postbox = context.account.postbox
    let initialRule = existing ?? LocalMessageFilterRule(pattern: "", chatId: chatId)
    let draft = Atomic(value: initialRule)
    let state = ValuePromise(initialRule, ignoreRepeated: true)
    let updateDraft: (@escaping (inout LocalMessageFilterRule) -> Void) -> Void = { change in
        state.set(draft.modify { current in
            var next = current
            change(&next)
            return next
        })
    }

    let signal = state.get() |> map { rule -> InputDataSignalValue in
        var entries: [InputDataEntry] = [
            .sectionId(0, type: .normal),
            .input(sectionId: 1, index: 0, value: .string(rule.pattern), error: nil, identifier: patternId, mode: .plain, data: InputDataRowData(viewType: .singleItem), placeholder: nil, inputPlaceholder: localizedString("Gergram.Chat.FilterPattern"), filter: { $0 }, limit: Int32(LocalMessageFilterEvaluation.maximumPatternLength)),
            .sectionId(1, type: .normal),
            .general(sectionId: 2, index: 0, value: .none, error: nil, identifier: InputDataIdentifier("enabled"), data: .init(name: localizedString("Gergram.Chat.FilterRuleEnabled"), color: theme.colors.text, type: .switchable(rule.isEnabled), viewType: .firstItem, action: {
                updateDraft { $0.isEnabled.toggle() }
            })),
            .general(sectionId: 2, index: 1, value: .none, error: nil, identifier: InputDataIdentifier("case-insensitive"), data: .init(name: localizedString("Gergram.Chat.FilterCaseInsensitive"), color: theme.colors.text, type: .switchable(rule.isCaseInsensitive), viewType: .innerItem, action: {
                updateDraft { $0.isCaseInsensitive.toggle() }
            })),
            .general(sectionId: 2, index: 2, value: .none, error: nil, identifier: InputDataIdentifier("reversed"), data: .init(name: localizedString("Gergram.Chat.FilterReversed"), color: theme.colors.text, type: .switchable(rule.isReversed), viewType: .lastItem, action: {
                updateDraft { $0.isReversed.toggle() }
            })),
            .sectionId(2, type: .normal)
        ]
        if let existing {
            entries.append(.general(sectionId: 3, index: 0, value: .none, error: nil, identifier: InputDataIdentifier("remove"), data: .init(name: strings().contextRemove, color: theme.colors.redUI, type: .none, viewType: .singleItem, action: {
                guard !context.isFrozen else { return }
                _ = updateLocalMessageFilterPreferences(postbox) { preferences in
                    if preferences.rules.first(where: { $0.id == existing.id }) == existing {
                        preferences.remove(ruleId: existing.id)
                    }
                }.startStandalone()
                context.bindings.rootNavigation().back()
            })))
            entries.append(.sectionId(3, type: .normal))
        }
        return InputDataSignalValue(entries: entries)
    }

    return InputDataController(dataSignal: signal, title: localizedString(existing == nil ? "Gergram.Chat.AddFilterRule" : "Gergram.Chat.EditFilterRule"), validateData: { data in
        guard !context.isFrozen else { return .none }
        var rule = draft.with { $0 }
        rule.pattern = data[patternId]?.stringValue ?? rule.pattern
        guard LocalMessageFilterEvaluation.isValid(rule) else {
            return .fail(.alert(localizedString("Gergram.Chat.InvalidFilterPattern")))
        }
        return .fail(.doSomething(next: { finish in
            _ = (updateLocalMessageFilterPreferences(postbox) { preferences -> Bool in
                guard preferences.rules.first(where: { $0.id == rule.id }) == existing else { return false }
                return preferences.upsert(rule)
            } |> deliverOnMainQueue).startStandalone(next: { saved in
                finish(saved ? .success(.navigationBack) : .fail(.alert(localizedString("Gergram.Chat.FilterRuleSaveFailed"))))
            })
        }))
    }, updateDatas: { data in
        if let pattern = data[patternId]?.stringValue {
            updateDraft { $0.pattern = pattern }
        }
        return .none
    })
}

private final class LocalMessageFilterChatPickerBehavior: SelectChatsBehavior {
    override func filterPeer(_ peer: Peer) -> Bool {
        super.filterPeer(peer) && LocalMessageFilterPreferences.acceptsChat(peer.id)
    }
}

func localMessageFiltersController(context: any AccountContextProtocol, chatId: PeerId? = nil, chatTitle: String? = nil) -> InputDataController {
    let postbox = context.account.postbox
    let pickerDisposable = MetaDisposable()
    let openEditor: (LocalMessageFilterRule?) -> Void = { existing in
        guard !context.isFrozen else { return }
        context.bindings.rootNavigation().push(localMessageFilterEditor(context: context, chatId: chatId, existing: existing))
    }

    let signal = localMessageFilterPreferences(postbox) |> map { preferences -> InputDataSignalValue in
        var entries: [InputDataEntry] = [.sectionId(0, type: .normal)]
        if chatId == nil {
            entries.append(.general(sectionId: 1, index: 0, value: .none, error: nil, identifier: InputDataIdentifier("enable-filters"), data: .init(name: localizedString("Gergram.Chat.EnableMessageFilters"), color: theme.colors.text, type: .switchable(preferences.isEnabled), viewType: .firstItem, action: {
                guard !context.isFrozen else { return }
                _ = updateLocalMessageFilterPreferences(postbox) { $0.isEnabled = !preferences.isEnabled }.startStandalone()
            })))
            entries.append(.general(sectionId: 1, index: 1, value: .none, error: nil, identifier: InputDataIdentifier("include-chats"), data: .init(name: localizedString("Gergram.Chat.FilterIncludeChats"), color: theme.colors.text, type: .switchable(preferences.includesChats), viewType: .innerItem, action: {
                guard !context.isFrozen else { return }
                _ = updateLocalMessageFilterPreferences(postbox) { $0.includesChats = !preferences.includesChats }.startStandalone()
            })))
            entries.append(.general(sectionId: 1, index: 2, value: .none, error: nil, identifier: InputDataIdentifier("chat-filters"), data: .init(name: localizedString("Gergram.Chat.ChatFilterRules"), color: theme.colors.text, type: .next, viewType: .innerItem, action: {
                guard !context.isFrozen else { return }
                let behavior = LocalMessageFilterChatPickerBehavior(settings: [.contacts, .bots, .groups, .channels], excludePeerIds: [context.peerId], limit: 1)
                let selection = selectModalPeers(window: context.window, context: context, title: localizedString("Gergram.Chat.ChatFilterRules"), behavior: behavior)
                pickerDisposable.set((selection |> mapToSignal { selected -> Signal<(PeerId, String?)?, NoError> in
                    guard let id = selected.first, LocalMessageFilterPreferences.acceptsChat(id) else { return .single(nil) }
                    return context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: id)) |> map { (id, $0?._asPeer().displayTitle) }
                } |> deliverOnMainQueue).start(next: { result in
                    guard !context.isFrozen, let (id, title) = result else { return }
                    context.bindings.rootNavigation().push(localMessageFiltersController(context: context, chatId: id, chatTitle: title))
                }))
            })))
            entries.append(.general(sectionId: 1, index: 3, value: .none, error: nil, identifier: InputDataIdentifier("import-filters"), data: .init(name: localizedString("Gergram.Chat.FilterTransferImport"), color: theme.colors.accent, type: .none, viewType: .innerItem, action: {
                LocalMessageFilterTransferActions.importRules(context: context)
            })))
            entries.append(.general(sectionId: 1, index: 4, value: .none, error: nil, identifier: InputDataIdentifier("export-filters"), data: .init(name: localizedString("Gergram.Chat.FilterTransferExport"), color: theme.colors.accent, type: .none, viewType: .lastItem, action: {
                LocalMessageFilterTransferActions.exportRules(context: context)
            })))
        }
        entries.append(.sectionId(1, type: .normal))
        entries.append(.general(sectionId: 2, index: 0, value: .none, error: nil, identifier: InputDataIdentifier("add-rule"), data: .init(name: localizedString("Gergram.Chat.AddFilterRule"), color: theme.colors.accent, type: .none, viewType: .singleItem, action: {
            guard preferences.rules.count < LocalMessageFilterPreferences.maximumRules else {
                alert(for: context.window, info: localizedString("Gergram.Chat.FilterRuleSaveFailed"))
                return
            }
            openEditor(nil)
        })))
        entries.append(.sectionId(2, type: .normal))

        let rules = preferences.rules.filter { $0.chatId == chatId }
        for (index, rule) in rules.enumerated() {
            let label = rule.pattern.replacingOccurrences(of: "\n", with: " ")
            let type: GeneralInteractedType = rule.isEnabled ? .next : .nextContext(localizedString("Gergram.Chat.FilterRuleDisabled"))
            entries.append(.general(sectionId: 3, index: Int32(index), value: .none, error: nil, identifier: InputDataIdentifier("rule-\(rule.id.uuidString)"), data: .init(name: label, color: theme.colors.text, type: type, viewType: bestGeneralViewType(rules, for: index), action: {
                openEditor(rule)
            })))
        }
        if let chatId {
            let shared = preferences.rules.filter { $0.chatId == nil }
            let excluded = preferences.excludedSharedRuleIds[chatId] ?? []
            if !shared.isEmpty {
                entries.append(.sectionId(3, type: .normal))
                entries.append(.desc(sectionId: 4, index: 0, text: .plain(localizedString("Gergram.Chat.SharedFilterRulesHere")), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
                for (index, rule) in shared.enumerated() {
                    let label = rule.pattern.replacingOccurrences(of: "\n", with: " ")
                    entries.append(.general(sectionId: 4, index: Int32(index + 1), value: .none, error: nil, identifier: InputDataIdentifier("shared-\(rule.id.uuidString)"), data: .init(name: label, color: theme.colors.text, type: .switchable(!excluded.contains(rule.id)), viewType: bestGeneralViewType(shared, for: index), action: {
                        guard !context.isFrozen else { return }
                        _ = (updateLocalMessageFilterPreferences(postbox) {
                            $0.setSharedRuleExcluded(rule.id, chatId: chatId, excluded: !excluded.contains(rule.id))
                        } |> deliverOnMainQueue).startStandalone(next: { saved in
                            if !saved { alert(for: context.window, info: localizedString("Gergram.Chat.FilterRuleSaveFailed")) }
                        })
                    })))
                }
            }
        }
        return InputDataSignalValue(entries: entries)
    }

    let title = chatTitle.map { String(format: localizedString("Gergram.Chat.FilterRulesForChat"), $0) }
        ?? localizedString(chatId == nil ? "Gergram.Chat.MessageFilters" : "Gergram.Chat.ChatFilterRules")
    let controller = InputDataController(dataSignal: signal, title: title, removeAfterDisappear: false, hasDone: false)
    controller.onDeinit = { pickerDisposable.dispose() }
    return controller
}

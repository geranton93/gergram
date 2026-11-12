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

private final class ShadowBanSenderPickerBehavior: SelectChatsBehavior {
    private let accountPeerId: PeerId

    init(accountPeerId: PeerId, excludedPeerIds: Set<PeerId>) {
        self.accountPeerId = accountPeerId
        super.init(settings: [.contacts, .channels, .bots], excludePeerIds: Array(excludedPeerIds), limit: 1)
    }

    override func filterPeer(_ peer: Peer) -> Bool {
        super.filterPeer(peer) && canHideSenderLocally(peer, accountPeerId: accountPeerId)
    }
}

public func localShadowBannedSendersController(context: any AccountContextProtocol) -> InputDataController {
    let postbox = context.account.postbox
    let accountPeerId = context.peerId
    let pickerDisposable = MetaDisposable()
    let senderList = localShadowBannedSenderIds(postbox) |> mapToSignal { senderIds -> Signal<[(PeerId, String)], NoError> in
        guard !senderIds.isEmpty else { return .single([]) }
        let items = senderIds.map { TelegramEngine.EngineData.Item.Peer.Peer(id: $0) }
        return context.engine.data.subscribe(EngineDataMap(items)) |> map { peers in
            return senderIds.map { peerId in
                let title = peers[peerId].flatMap { $0 }?._asPeer().displayTitle
                    ?? String(format: localizedString("Gergram.Chat.UnavailableSender"), peerId.description)
                return (peerId, title)
            }.sorted { lhs, rhs in
                let order = lhs.1.localizedStandardCompare(rhs.1)
                return order == .orderedSame ? lhs.0 < rhs.0 : order == .orderedAscending
            }
        }
    }

    let signal = senderList |> map { senders -> InputDataSignalValue in
        var entries: [InputDataEntry] = [
            .sectionId(0, type: .normal),
            .general(sectionId: 1, index: 0, value: .none, error: nil, identifier: InputDataIdentifier("add-sender"), data: .init(name: localizedString("Gergram.Chat.AddShadowBannedSender"), color: theme.colors.accent, type: .none, viewType: .singleItem, action: {
                guard !context.isFrozen else { return }
                let behavior = ShadowBanSenderPickerBehavior(accountPeerId: accountPeerId, excludedPeerIds: Set(senders.map { $0.0 }))
                let selection = selectModalPeers(window: context.window, context: context, title: localizedString("Gergram.Chat.AddShadowBannedSender"), behavior: behavior)
                pickerDisposable.set((selection |> deliverOnMainQueue).start(next: { peerIds in
                    guard !context.isFrozen, let peerId = peerIds.first else { return }
                    _ = setLocalShadowBan(postbox, senderId: peerId, accountPeerId: accountPeerId, hidden: true).startStandalone()
                }))
            })),
            .desc(sectionId: 1, index: 1, text: .plain(localizedString("Gergram.Chat.ShadowBannedSendersDescription")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)),
            .sectionId(1, type: .normal)
        ]
        for (index, sender) in senders.enumerated() {
            let (peerId, title) = sender
            entries.append(.general(sectionId: 2, index: Int32(index), value: .none, error: nil, identifier: InputDataIdentifier("sender-\(peerId)"), data: .init(name: title, color: theme.colors.text, type: .context(strings().contextRemove), viewType: bestGeneralViewType(senders, for: index), action: {
                guard !context.isFrozen else { return }
                _ = setLocalShadowBan(postbox, senderId: peerId, accountPeerId: accountPeerId, hidden: false).startStandalone()
            })))
        }
        return InputDataSignalValue(entries: entries)
    }

    let controller = InputDataController(dataSignal: signal, title: localizedString("Gergram.Chat.ShadowBannedSenders"), hasDone: false)
    controller.onDeinit = { pickerDisposable.dispose() }
    return controller
}

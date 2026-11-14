import Foundation

private func expect(_ value: @autoclosure () -> Bool, _ name: String) {
    precondition(value(), name)
    print("PASS \(name)")
}

private func peer(_ namespace: PeerId.Namespace, _ id: Int64) -> PeerId {
    PeerId(namespace: namespace, id: ._internalFromInt64Value(id))
}

@main
private enum CaptureTests {
    static func main() {
        let account = peer(Namespaces.Peer.CloudUser, 1)
        let sender = TelegramUser(id: peer(Namespaces.Peer.CloudUser, 2))
        let bot = TelegramUser(id: peer(Namespaces.Peer.CloudUser, 3), botInfo: true)
        let group = TelegramGroup(id: peer(Namespaces.Peer.CloudGroup, 11))
        let channel = TelegramChannel(id: peer(Namespaces.Peer.CloudChannel, 11))
        let id = MessageId(peerId: channel.id, namespace: Namespaces.Message.Cloud, id: 10)
        let groupId = MessageId(peerId: group.id, namespace: Namespaces.Message.Cloud, id: id.id)
        let privateId = MessageId(peerId: sender.id, namespace: Namespaces.Message.Cloud, id: 5)
        let replay = ReplayContext(accountPeerId: account)
        let transaction = replay.transaction
        transaction.peers = [sender.id: sender, group.id: group, channel.id: channel]
        transaction.globalIds = [5: privateId, 10: groupId]
        let entities = [
            MessageTextEntity(range: 0 ..< 2, type: .Bold),
            MessageTextEntity(range: 3 ..< 4, type: .TextMention(peerId: sender.id)),
            MessageTextEntity(range: 3 ..< 4, type: .CustomEmoji(stickerPack: .iconStatusEmoji, fileId: 123)),
        ]
        let caption = Message(id: id, threadId: 4, author: sender, text: "😀 a", attributes: [TextEntitiesMessageAttribute(entities: entities)], media: [TelegramMediaImage()])
        transaction.messages = [id: caption, groupId: Message(id: groupId, author: sender), privateId: Message(id: privateId, author: sender)]
        let edit = StoreMessage(id: .Id(id), authorId: sender.id)

        replay.archiveDeletedGlobalMessages([10], revision: 15)
        replay.archiveDeletedMessages([id], revision: 15)
        replay.archiveEditedMessage(id, updated: edit, revision: 16)
        expect(transaction.archiveWrites.isEmpty && transaction.globalLookupCount == 0 && transaction.messageLookupCount == 0, "default off skips global mapping and message reads")

        transaction.updateLocalArchiveCaptureSettings(.init(captureDeletions: true))
        expect(transaction.localArchiveCaptureSettings() == .init(captureDeletions: true), "independent account settings round trip")
        replay.archiveDeletedGlobalMessages([10], revision: nil)
        replay.archiveDeletedMessages([id], revision: 0)
        replay.archiveEditedMessage(id, updated: edit, revision: 16)
        expect(transaction.archiveWrites.isEmpty && transaction.globalLookupCount == 0, "unmarked and nonpositive revisions and disabled edits are ignored")
        replay.archiveDeletedGlobalMessages([10, 5, 99], revision: 15)
        expect(transaction.archiveWrites.count == 1 && transaction.archiveWrites[0].messages.map(\.id.message) == [groupId], "global ids resolve locally and unknown direct-chat protection fails closed")
        transaction.cachedUsers[sender.id] = CachedUserData(flags: [.myCopyProtectionEnabled])
        replay.archiveDeletedGlobalMessages([5], revision: 16)
        transaction.cachedUsers[sender.id] = CachedUserData(flags: [.copyProtectionEnabled])
        replay.archiveDeletedGlobalMessages([5], revision: 17)
        expect(transaction.archiveWrites.count == 1, "both directions of private copy protection are respected")
        transaction.cachedUsers[sender.id] = CachedUserData()
        replay.archiveDeletedGlobalMessages([5], revision: 18)
        expect(transaction.archiveWrites.last?.messages.first?.id.message == privateId, "eligible private message archives")

        replay.archiveDeletedMessages([id], revision: 19)
        let captured = transaction.archiveWrites.last!.messages[0]
        let snapshot = LocalArchiveSnapshot.decode(captured.snapshot)
        expect(transaction.archiveWrites.last?.account == account.toInt64() && captured.id == .init(message: id, threadId: 4, kind: .deletion, revision: 19), "channel delete records account, peer, forum topic and server identity")
        expect(snapshot?.text == caption.text && snapshot?.timestamp == caption.timestamp && snapshot?.authorId == sender.id, "typed caption snapshot round trip")
        expect(snapshot?.entities == Array(entities.prefix(2)) + [MessageTextEntity(range: 3 ..< 4, type: .CustomEmoji(stickerPack: nil, fileId: 123))], "text formatting, mention and custom emoji survive serialization")
        replay.archiveDeletedMessages([id], revision: 19)
        expect(transaction.archiveWrites.last?.messages.first?.id == captured.id, "duplicate server event produces the same storage identity")

        let pending = transaction.archiveWrites.count
        let excluded: [Message] = [
            Message(id: id, flags: [], author: sender),
            Message(id: id, flags: [.Incoming, .CopyProtected], author: sender),
            Message(id: id, forwardInfo: true, author: sender),
            Message(id: id, author: TelegramUser(id: account)),
            Message(id: id, author: nil),
            Message(id: id, author: bot),
            Message(id: id, author: sender, text: ""),
            Message(id: id, author: sender, attributes: [InlineBotMessageAttribute()]),
            Message(id: id, author: sender, attributes: [AutoclearTimeoutMessageAttribute()]),
            Message(id: id, author: sender, attributes: [AutoremoveTimeoutMessageAttribute()]),
            Message(id: id, author: sender, attributes: [EphemeralReplacementMessageAttribute()]),
            Message(id: id, author: sender, attributes: [EphemeralMessageAttribute()]),
            Message(id: id, author: sender, attributes: [EphemeralOutgoingMessageAttribute()]),
            Message(id: id, author: sender, attributes: [PaidStarsMessageAttribute()]),
            Message(id: id, author: sender, attributes: [RestrictedContentMessageAttribute()]),
            Message(id: id, author: sender, attributes: [RichTextMessageAttribute()]),
            Message(id: id, author: sender, attributes: [MediaSpoilerMessageAttribute()]),
            Message(id: id, author: sender, attributes: [TextEntitiesMessageAttribute(entities: [.init(range: 0 ..< 1, type: .Spoiler)])]),
            Message(id: id, author: sender, attributes: [TextEntitiesMessageAttribute(entities: [.init(range: 0 ..< 8, type: .Bold)])]),
            Message(id: id, author: sender, media: [TelegramMediaPaidContent()]),
            Message(id: id, author: sender, text: String(repeating: "x", count: 16385)),
        ]
        for message in excluded {
            transaction.messages[id] = message
            replay.archiveDeletedMessages([id], revision: 20)
        }
        let scheduled = MessageId(peerId: channel.id, namespace: 3, id: 10)
        transaction.messages[scheduled] = Message(id: scheduled, author: sender)
        replay.archiveDeletedMessages([scheduled], revision: 20)
        expect(transaction.archiveWrites.count == pending, "nonordinary, protected, private, invalid and unbounded content is excluded")
        transaction.messages[id] = caption
        replay.finalState.state.peers[channel.id] = TelegramChannel(id: channel.id, isCopyProtectionEnabled: true)
        replay.archiveDeletedMessages([id], revision: 20)
        expect(transaction.archiveWrites.count == pending, "copy protection learned in the same update batch excludes capture")
        replay.finalState.state.peers.removeAll()

        transaction.updateLocalArchiveCaptureSettings(.init(captureDeletions: true, captureBots: true))
        transaction.messages[id] = Message(id: id, author: bot)
        replay.archiveDeletedMessages([id], revision: 21)
        expect(transaction.archiveWrites.count == pending + 1, "bot capture requires its own opt-in")

        transaction.updateLocalArchiveCaptureSettings(.init(captureEdits: true))
        transaction.messages[id] = caption
        replay.archiveDeletedMessages([id], revision: 22)
        expect(transaction.archiveWrites.count == pending + 1, "edit opt-in leaves deletions disabled")
        replay.archiveEditedMessage(id, updated: edit, revision: 23)
        let archivedEdit = transaction.archiveWrites.last!.messages[0]
        expect(archivedEdit.id.kind == .edit && archivedEdit.id.revision == 23 && LocalArchiveSnapshot.decode(archivedEdit.snapshot)?.text == caption.text, "edit capture stores the previous revision")
        expect(transaction.messages[id]?.text == caption.text, "capture does not mutate live chat")
        let afterEdit = transaction.archiveWrites.count
        let unchanged = StoreMessage(id: .Id(id), authorId: sender.id, text: caption.text, attributes: caption.attributes)
        let hidden = StoreMessage(id: .Id(id), authorId: sender.id, attributes: [EditedMessageAttribute(date: 100, isHidden: true)])
        let protected = StoreMessage(id: .Id(id), flags: [.Incoming, .CopyProtected], authorId: sender.id)
        let mismatched = StoreMessage(id: .Id(groupId), authorId: sender.id)
        let timed = StoreMessage(id: .Id(id), authorId: sender.id, attributes: [AutoremoveTimeoutMessageAttribute()])
        let wrongAuthor = StoreMessage(id: .Id(id), authorId: account)
        for excludedEdit in [unchanged, hidden, protected, mismatched, timed, wrongAuthor] {
            replay.archiveEditedMessage(id, updated: excludedEdit, revision: 24)
        }
        let fresh = Message(id: id, author: sender, attributes: [ChannelMessageStateVersionAttribute(pts: 25)])
        transaction.messages[id] = fresh
        replay.archiveEditedMessage(id, updated: edit, revision: 24)
        expect(transaction.archiveWrites.count == afterEdit, "unchanged, hidden, protected, timed, self, mismatched and stale edits are ignored")
        transaction.messages[id] = caption
        replay.archiveEditedMessage(id, updated: StoreMessage(id: .Id(id), authorId: sender.id, text: caption.text), revision: 26)
        replay.archiveEditedMessage(id, updated: StoreMessage(id: .Id(id), authorId: sender.id, text: ""), revision: 27)
        expect(transaction.archiveWrites.count == afterEdit + 2, "format-only edits and caption removal are substantive")

        transaction.updateLocalArchiveCaptureSettings(.init(captureDeletions: true))
        let large = (101 ... 230).map { number in
            MessageId(peerId: channel.id, namespace: Namespaces.Message.Cloud, id: Int32(number))
        }
        for id in large {
            transaction.messages[id] = Message(id: id, author: sender)
        }
        replay.archiveDeletedMessages(large, revision: 28)
        expect(transaction.archiveWrites.suffix(2).map { $0.messages.count } == [128, 2], "large deletes use storage-sized batches")

        let malformed = [
            "{\"version\":2,\"text\":\"x\",\"timestamp\":1,\"entities\":[]}",
            "{\"version\":1,\"text\":\"x\",\"timestamp\":1,\"author\":-1,\"entities\":[]}",
            "{\"version\":1,\"text\":\"x\",\"timestamp\":1,\"entities\":[{\"start\":0,\"end\":1,\"_rawValue\":11,\"peerId\":-1}]}",
            "{\"version\":1,\"text\":\"x\",\"timestamp\":1,\"entities\":[{\"start\":0,\"end\":1,\"_rawValue\":18,\"f\":1,\"s\":{\"r\":99}}]}",
            "{\"version\":1,\"text\":\"x\",\"timestamp\":1,\"entities\":[{\"start\":1,\"end\":0,\"_rawValue\":6}]}",
            "{\"version\":1,\"text\":\"x\",\"timestamp\":1,\"entities\":[{\"start\":0,\"end\":1,\"_rawValue\":17}]}",
        ]
        expect(malformed.allSatisfy { LocalArchiveSnapshot.decode(Data($0.utf8)) == nil }, "corrupt, unsupported and private snapshots fail closed")
        expect(LocalArchiveSnapshot.decode(Data(repeating: 1, count: 32769)) == nil, "oversized payload rejected before decoding")
    }
}

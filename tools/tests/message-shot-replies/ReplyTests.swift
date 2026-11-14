import AppKit

enum Namespaces {
    enum Peer { static let CloudUser = 0, CloudGroup = 1, CloudChannel = 2, SecretChat = 3 }
    enum Message { static let Cloud = 0, Local = 1 }
}
struct PeerId: Hashable {
    var namespace = Namespaces.Peer.CloudUser
    var id = 1
}
struct MessageId: Hashable {
    var peerId = PeerId()
    var namespace = Namespaces.Message.Cloud
    var id = 1
}
protocol MessageAttribute {}
struct MessageTextEntity {
    enum EntityType { case Spoiler }
    var type: EntityType = .Spoiler
}
struct TextEntitiesMessageAttribute: MessageAttribute {
    var entities: [MessageTextEntity] = []
}
struct EngineMessageReplyQuote {
    var text = ""
    var offset: Int?
    var entities: [MessageTextEntity] = []
    var richText: String?
}
struct ReplyMessageAttribute {
    var messageId = MessageId()
    var innerSubject: Int?
    var isQuote = false
    var quote: EngineMessageReplyQuote?
}
struct Author { var displayTitle = "Author" }
struct Message {
    var id = MessageId()
    var stableVersion: UInt32 = 1
    var replyAttribute: ReplyMessageAttribute?
    var attributes: [any MessageAttribute] = []
    var effectiveAuthor: Author? = Author()
    var text = "Body"
    var exportable = true
    var safePreview = true
}
enum ChatRowItem {
    static func hidesReply(to reply: ReplyMessageAttribute, in message: Message, threadId: Int64?) -> Bool {
        threadId == Int64(reply.messageId.id)
    }
}
enum BlockedSenderVisibilitySettings {
    static var isEnabled = false
}
struct ChatLocalMessageVisibility {
    static func get(_ account: Int) -> Self { Self() }
    func isHidden(_ target: Message) -> Bool { false }
}
struct ChatInteraction {
    struct Context { let account = 0 }
    struct Location { var threadId: Int64? }
    var interactionContext = Context()
    var chatLocation = Location()
}
struct LocalizedStrings {
    func chatReplyMessagePanelTitle(_ author: String) -> String { "Reply to " + author }
    func chatReplyQuotePanelTitle(_ author: String) -> String { "Quote from " + author }
}
func strings() -> LocalizedStrings { LocalizedStrings() }
func localizedString(_ key: String) -> String {
    switch key {
    case "Gergram.Chat.MessageShotExternalReplyTitle": return __EXTERNAL_TITLE__
    case "Gergram.Chat.MessageShotExternalReplyText": return __EXTERNAL_TEXT__
    default: fatalError("Unexpected key \(key)")
    }
}

enum MessageShotReplyTests {
    private struct Snapshot {
        var messages: [Message]
        var replyTargets: [MessageId: Message] = [:]
        var cachedData: String?
    }
    __TYPES__
    __RESOLVE_REPLY__
    __RENDER_REPLY__

    private static func supportsMessage(_ message: Message, interaction: ChatInteraction, cachedData: String?) -> Bool {
        message.exportable
    }

    private static func supportsPreview(_ message: Message, interaction: ChatInteraction) -> Bool {
        message.safePreview
    }

    static func run() {
        let interaction = ChatInteraction()
        let localTarget = MessageId(id: 2)
        let externalTarget = MessageId(peerId: PeerId(namespace: Namespaces.Peer.CloudChannel, id: 99), id: 2)
        let local = Message(replyAttribute: ReplyMessageAttribute(messageId: localTarget))
        var external = Message(id: MessageId(id: 3), replyAttribute: ReplyMessageAttribute(messageId: externalTarget, isQuote: true, quote: EngineMessageReplyQuote(text: "Copied secret", entities: [MessageTextEntity()])))
        let original = Message(id: localTarget, text: "Verified local text")
        var reads: [MessageId] = []
        let targets = loadLocalReplyTargets(for: [local, external, local], threadId: nil) { id in
            reads.append(id)
            return id == localTarget ? original : nil
        }
        precondition(reads == [localTarget])
        let snapshot = Snapshot(messages: [local, external], replyTargets: targets)
        let blocks = replyBlocks(in: snapshot, interaction: interaction)
        precondition(blocks[local.id] == .local(ReplyExcerpt(target: localTarget, version: 1, title: "Reply to Author", text: original.text)))
        precondition(blocks[external.id] == .external)
        print("PASS only verified same-chat targets are loaded and excerpts stay local")

        func render(_ block: ReplyBlock) -> Data {
            let reply = renderReply(block, accent: .systemBlue, textColor: .black)
            precondition(reply.title.string == "Reply" && reply.excerpt.string == "Message in another chat")
            let row = MessageShotRenderer.Row(header: NSAttributedString(string: "Author"), body: NSAttributedString(string: "Body"), background: .white, reply: reply, attachments: [], footer: nil)
            let png = MessageShotRenderer.png(rows: [row], background: nil)!
            precondition(NSBitmapImageRep(data: png) != nil)
            return png
        }
        let firstPNG = render(blocks[external.id]!)
        external.replyAttribute?.quote = EngineMessageReplyQuote(text: "Different protected copied text", richText: "Potential rich private content")
        let protectedTarget = Message(id: externalTarget, effectiveAuthor: Author(displayTitle: "Private name"), text: "Protected origin", exportable: false, safePreview: false)
        let changed = Snapshot(messages: [external], replyTargets: [externalTarget: protectedTarget])
        precondition(render(replyBlocks(in: changed, interaction: interaction)[external.id]!) == firstPNG)
        print("PASS foreign author, content, quote, and spoiler cannot affect exported PNG")

        BlockedSenderVisibilitySettings.isEnabled = true
        let blocked = replyBlocks(in: snapshot, interaction: interaction)
        precondition(blocked[local.id] == nil && blocked[external.id] == .external)
        BlockedSenderVisibilitySettings.isEnabled = false
        var restricted = original
        restricted.exportable = false
        precondition(replyBlocks(in: Snapshot(messages: [local], replyTargets: [localTarget: restricted]), interaction: interaction).isEmpty)
        restricted.exportable = true
        restricted.safePreview = false
        precondition(replyBlocks(in: Snapshot(messages: [local], replyTargets: [localTarget: restricted]), interaction: interaction).isEmpty)
        print("PASS existing local protection remains in effect")

        let invalid = [
            ReplyMessageAttribute(messageId: externalTarget, innerSubject: 1),
            ReplyMessageAttribute(messageId: MessageId(peerId: externalTarget.peerId, namespace: Namespaces.Message.Local, id: 2)),
            ReplyMessageAttribute(messageId: MessageId(peerId: PeerId(namespace: Namespaces.Peer.SecretChat, id: 99), id: 2)),
            ReplyMessageAttribute(messageId: MessageId(peerId: externalTarget.peerId, id: 0)),
            ReplyMessageAttribute(messageId: external.id)
        ]
        for reply in invalid {
            external.replyAttribute = reply
            precondition(replyBlocks(in: Snapshot(messages: [external]), interaction: interaction).isEmpty)
        }
        let sameNumberThread = ChatInteraction(chatLocation: .init(threadId: 2))
        external.replyAttribute = ReplyMessageAttribute(messageId: externalTarget)
        precondition(replyBlocks(in: Snapshot(messages: [external]), interaction: sameNumberThread)[external.id] == .external)
        precondition(replyBlocks(in: Snapshot(messages: [local], replyTargets: targets), interaction: sameNumberThread).isEmpty)
        print("PASS invalid references are omitted and same-number thread roots are not confused")
    }
}

MessageShotReplyTests.run()

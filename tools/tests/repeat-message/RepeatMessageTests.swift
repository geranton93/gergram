import Foundation
import SwiftSignalKit
import XCTest

struct PeerId: Equatable, Hashable {
    let namespace: Int
    let value: Int
    static let me = Self(namespace: Namespaces.Peer.CloudUser, value: 1)
    static let user = Self(namespace: Namespaces.Peer.CloudUser, value: 2)
    static let group = Self(namespace: Namespaces.Peer.CloudGroup, value: 3)
    static let forum = Self(namespace: Namespaces.Peer.CloudChannel, value: 4)
}
struct MessageId: Equatable, Hashable {
    let peerId: PeerId
    var namespace = Namespaces.Message.Cloud
    var id = 5
}
enum Namespaces {
    enum Peer { static let CloudUser = 0; static let CloudGroup = 1; static let CloudChannel = 2 }
    enum Message { static let Cloud = 0 }
    enum Media { static let CloudImage = 1 }
}
struct Stars { let value: Int64 }
protocol CachedPeerData {}
struct CachedUserData: CachedPeerData {
    struct Flags: OptionSet {
        let rawValue: Int
        static let premiumRequired = Self(rawValue: 1)
    }
    var flags: Flags = []
    var protected = false
    var sendPaidMessageStars: Stars?
}
class Peer {
    let id: PeerId
    var isMonoForum = false
    var isForumOrMonoForum = false
    var isCopyProtectionEnabled = false
    var isAdmin = false
    var restricted = false
    var canSend = true
    var bannedText = false
    init(_ id: PeerId) { self.id = id }
    func restrictionText(_ contentSettings: Int) -> String? { restricted ? "Restricted" : nil }
    func isCopyProtected(cachedData: CachedPeerData?) -> Bool { (cachedData as? CachedUserData)?.protected == true }
    var canSendPhoto = true
    var bannedPhoto = false
    func canSendMessage(_ inThread: Bool, media: Any? = nil, threadData: ThreadInfo?, cachedData: CachedPeerData?) -> Bool {
        canSend && (!(media is TelegramMediaImage) || canSendPhoto)
    }
}
final class TelegramUser: Peer {}
final class TelegramGroup: Peer {}
final class TelegramChannel: Peer {
    enum Info { case group, broadcast }
    enum Participation { case member, left }
    var info = Info.group
    var participationStatus = Participation.member
    var sendPaidMessageStars: Stars?
}
struct Thread: Equatable {
    let peerId: PeerId
    var threadId: Int64 = 21
    var isForumPost = true
    var isNotAvailable = false
    var effectiveTopId: MessageId { .init(peerId: peerId, id: Int(threadId)) }
}
enum ChatLocation: Equatable {
    case peer(PeerId)
    case thread(Thread)
    var peerId: PeerId {
        switch self {
        case let .peer(id): return id
        case let .thread(thread): return thread.peerId
        }
    }
    var threadId: Int64? {
        if case let .thread(thread) = self { return thread.threadId }
        return nil
    }
    var threadMsgId: MessageId? {
        if case let .thread(thread) = self { return thread.effectiveTopId }
        return nil
    }
}
enum ChatMode: Equatable {
    enum ThreadMode: Equatable { case topic(origin: MessageId), replies(origin: MessageId) }
    case history, thread(ThreadMode), scheduled
    var isThreadMode: Bool {
        if case .thread = self { return true }
        return false
    }
}
enum TextEntityType: Equatable {
    case Unknown, PhoneNumber, Custom, TextMention, CustomEmoji
    case Bold, Spoiler, TextUrl(String)
}
struct MessageTextEntity: Equatable {
    let range: Range<Int>
    let type: TextEntityType
}
protocol MessageAttribute {}
struct TextEntitiesMessageAttribute: MessageAttribute { let entities: [MessageTextEntity] }
struct OutgoingContentInfoMessageAttribute: MessageAttribute {
    struct Flags: OptionSet {
        let rawValue: Int
        static let disableLinkPreviews = Self(rawValue: 1)
    }
    let flags: Flags
}
struct NotificationInfoMessageAttribute: MessageAttribute {
    struct Flags: OptionSet {
        let rawValue: Int
        static let muted = Self(rawValue: 1)
    }
    let flags: Flags
}
struct EphemeralMessageAttribute: MessageAttribute {}
struct RestrictedContentMessageAttribute: MessageAttribute {}
struct RichTextMessageAttribute: MessageAttribute {}
struct PaidStarsMessageAttribute: MessageAttribute {}
struct InlineBotMessageAttribute: MessageAttribute {}
struct MessageFlags: OptionSet {
    let rawValue: Int
    static let Sending = Self(rawValue: 1)
    static let Failed = Self(rawValue: 2)
    static let Unsent = Self(rawValue: 4)
}
struct Message {
    static let newTopicThreadId: Int64 = -1
    var id: MessageId
    var author: Peer? = TelegramUser(.me)
    var threadId: Int64?
    var text = "👋  formatted  "
    var textEntities: TextEntitiesMessageAttribute? = .init(entities: [.init(range: 4..<13, type: .Bold)])
    var flags: MessageFlags = []
    var media: [Any] = []
    var groupingKey: Int64?
    var forwardInfo: Int?
    var replyMarkup: Int?
    var isScheduledMessage = false
    var containsSecretMedia = false
    var adAttribute: Int?
    var autoclearTimeout: Int?
    var autoremoveAttribute: Int?
    var activeEphemeralReplacementMessage: Int?
    var paidContent: Int?
    var publishedSuggestedPostMessageAttribute: Int?
    var attributes: [MessageAttribute] = []
    var protected = false
    var hidden = false
    var incoming = false
    var isMediaSpoilered = false
    var sensitive = false
    var hasMessageReference = true
    func effectivelyIncoming(_ peerId: PeerId) -> Bool { incoming }
    func isCopyProtected(cachedData: CachedPeerData?) -> Bool { protected }
    func isSensitiveContent(platform: String, contentSettings: Int) -> Bool { sensitive }
}
struct MediaId: Equatable {
    var namespace = Namespaces.Media.CloudImage
    let id: Int64
}
struct MessageReference {
    let id: MessageId?
    init(_ source: Message) { id = source.hasMessageReference ? source.id : nil }
}
struct CloudPhotoSizeMediaResource {}
struct TelegramMediaImageRepresentation {
    var resource: Any = CloudPhotoSizeMediaResource()
}
struct TelegramMediaImage {
    enum Reference { case cloud(Int64, Int64, Data?) }
    var imageId = MediaId(id: 10)
    var reference: Reference? = .cloud(10, 42, Data([1]))
    var representations: [TelegramMediaImageRepresentation] = [.init()]
    var video: Int?
    var videoRepresentations: [Int] = []
    var emojiMarkup: Int?
}
enum AnyMediaReference {
    case message(message: MessageReference, media: Any)
}
struct Reply: Equatable {
    let messageId: MessageId
    let quote: Int?
    let innerSubject: Int?
}
enum EnqueueMessage {
    case message(text: String, attributes: [MessageAttribute], inlineStickers: [Int: Int], mediaReference: AnyMediaReference?, threadId: Int64?, replyToMessageId: Reply?, replyToStoryId: Int?, localGroupingKey: Int?, correlationId: Int?, bubbleUpEmojiOrStickersets: [Int])
}
enum SendSound {
    case silent
    var notificationIsSilent: Bool? { true }
}
enum FastSettings {
    static func isChannelMessagesMuted(_ peerId: PeerId) -> Bool { false }
}
struct ThreadInfo { var isClosed = false; var isOwnedByMe = false }
enum ChatState { case normal, selecting }
struct SearchMode { var inSearch = false }
struct InterfaceState { var suggestPost: Int? }
struct Presentation {
    var state = ChatState.normal
    var reportMode: Int?
    var selectionState: Int?
    var searchMode = SearchMode()
    var isNotAccessible = false
    var isBlocked: Bool?
    var threadedBot = false
    var isMonoforum = false
    var currentSendAsPeerId: PeerId?
    var slowMode: Int?
    var slowModeMultipleLocked = false
    var sendPaidMessageStars: Stars?
    var interfaceState = InterfaceState()
    var peer: Peer?
    var cachedData: CachedPeerData?
    var threadInfo: ThreadInfo?
}
enum Right { case banSendText, banSendPhotos }
func permissionText(from peer: Peer, for right: Right, cachedData: CachedPeerData?) -> String? {
    (right == .banSendText ? peer.bannedText : peer.bannedPhoto) ? "Banned" : nil
}
func canForwardMessage(_ message: Message, chatInteraction: ChatInteraction) -> Bool { !message.protected }

final class Window {
    var isVisible = true
    let visibilityState = ValuePromise(true)
    var visibility: Signal<Bool, NoError> { visibilityState.get() }
}
struct AccountId: Equatable { let id: Int }
struct AccountRecord: Equatable { let id: AccountId }
struct Accounts: Equatable { var primary: AccountRecord? = .init(id: .init(id: 1)) }
final class SharedContext {
    let accounts = ValuePromise(Accounts())
    var activeAccounts: Signal<Accounts, NoError> { accounts.get() }
}
final class Context {
    let account = Account()
    let window = Window()
    let sharedContext = SharedContext()
    let engine = Engine()
    let peerId = PeerId.me
    let contentSettings = 0
    var isCurrent = true
    var isExternal = false
    var isFrozen = false
    var isPremium = false
    var premiumLimits = PremiumLimits()
}
struct PremiumLimits {
    var caption_length_limit_premium: Int32 = 2048
    var caption_length_limit_default: Int32 = 1024
}
final class Account {
    let id = AccountId(id: 1)
    let postbox = Postbox()
}
final class Engine {
    let peers = EnginePeers()
}
final class EnginePeers {
    var fetchCount = 0
    var refresh = Signal<Bool, NoError>.single(true)
    func fetchAndUpdateCachedPeerData(peerId: PeerId) -> Signal<Bool, NoError> {
        fetchCount += 1
        return refresh
    }
}
final class Postbox {
    var source: Message?
    var peer: Peer?
    var cached: CachedPeerData?
    var beforeRead: (() -> Void)?
    var readCount = 0
    func transaction<Value>(_ read: @escaping (Postbox) -> Value) -> Signal<Value, NoError> {
        readCount += 1
        beforeRead?()
        return .single(read(self))
    }
    func getMessage(_ id: MessageId) -> Message? { source?.id == id ? source : nil }
    func getPeer(_ id: PeerId) -> Peer? { peer?.id == id ? peer : nil }
    func getPeerCachedData(peerId: PeerId) -> CachedPeerData? { cached }
}
struct ChatLocalMessageVisibility {
    static func get(_ account: Account) -> Self { Self() }
    func isHidden(_ message: Message) -> Bool { message.hidden }
}
final class ChatInteraction {
    let repeatMessageAction = ChatRepeatMessageAction()
    let interactionContext = Context()
    var presentation = Presentation()
    var mode = ChatMode.history
    var chatLocation: ChatLocation
    var isLogInteraction = false
    var isGlobalSearchMessage = false
    var canAnimate = true
    var revision = 0
    var draft = "Existing draft"
    var peer: Peer? { presentation.peer }

    init(peer: Peer = TelegramGroup(.group), topic: Bool = false) {
        if topic {
            peer.isForumOrMonoForum = true
            let thread = Thread(peerId: peer.id)
            self.chatLocation = .thread(thread)
            self.mode = .thread(.topic(origin: thread.effectiveTopId))
        } else {
            self.chatLocation = .peer(peer.id)
        }
        presentation.peer = peer
        if peer is TelegramUser { presentation.cachedData = CachedUserData() }
        let postbox = interactionContext.account.postbox
        postbox.peer = peer
        postbox.cached = presentation.cachedData
        postbox.source = .init(id: .init(peerId: peer.id), threadId: chatLocation.threadId)
    }
    func canAnimateUpdates() -> Bool { canAnimate }
    func captureDeferredSendAction() -> ChatDeferredSendAction {
        let revision = self.revision
        return ChatDeferredSendAction { [weak self] in self?.revision == revision }
    }
    func resolvedSendSound() -> SendSound { .silent }
    func menu() -> ContextMenuItem? {
        guard let message = interactionContext.account.postbox.source else { return nil }
        return repeatMessageAction.menuItem(for: message, interaction: self)
    }
}

struct ContextMenuItem {
    let handler: () -> Void
    init(_ name: String, handler: @escaping () -> Void, itemImage: Int) { self.handler = handler }
}
enum MenuAnimation { enum menu_reload { static let value = 1 } }
struct ModalAlertData {
    enum Mode { case confirm(text: String, isThird: Bool) }
    let title: String
    let info: String
    let ok: String
    let mode: Mode
}
struct Prompt {
    let accept: () -> Void
    let cancel: () -> Void
    let dismiss: () -> Void
}
enum Fixture {
    static var prompts: [Prompt] = []
    static var alerts: [String] = []
    static var sent: [(PeerId, EnqueueMessage)] = []
    static var enqueue = Signal<[MessageId?], NoError>.single([.init(peerId: .group)])
}
func showDismissableModalAlert(for window: Window, data: ModalAlertData, completion: @escaping (Bool) -> Void, cancel: @escaping () -> Void, onDeinit: @escaping () -> Void) -> () -> Void {
    Fixture.prompts.append(.init(accept: { completion(true) }, cancel: cancel, dismiss: onDeinit))
    return onDeinit
}
func localizedString(_ key: String) -> String { key }
struct Strings { let modalSend = "Send"; let modalCancel = "Cancel" }
func strings() -> Strings { Strings() }
func alert(for window: Window, info: String) { Fixture.alerts.append(info) }
enum Sender {
    static func enqueue(message: EnqueueMessage, context: Context, peerId: PeerId) -> Signal<[MessageId?], NoError> {
        Fixture.sent.append((peerId, message))
        return Fixture.enqueue
    }
}

final class RepeatMessageTests: XCTestCase {
    override func setUp() {
        Fixture.prompts = []
        Fixture.alerts = []
        Fixture.sent = []
        Fixture.enqueue = .single([.init(peerId: .group)])
    }

    func testRepeatRetainsExactTextEntitiesAndDraftAndEnqueuesOnce() throws {
        let owner = ChatInteraction()
        let action = try XCTUnwrap(owner.menu())
        action.handler()
        action.handler()
        XCTAssertEqual(Fixture.prompts.count, 1)
        XCTAssertTrue(Fixture.sent.isEmpty)
        let prompt = Fixture.prompts[0]
        prompt.accept()
        prompt.accept()
        XCTAssertEqual(Fixture.sent.count, 1)
        let sent = try XCTUnwrap(Fixture.sent.first)
        XCTAssertEqual(sent.0, .group)
        guard case let .message(text, attributes, stickers, media, thread, reply, story, grouping, correlation, packs) = sent.1 else {
            return XCTFail("Expected text")
        }
        XCTAssertEqual(text, "👋  formatted  ")
        XCTAssertEqual((attributes.first as? TextEntitiesMessageAttribute)?.entities, [.init(range: 4..<13, type: .Bold)])
        XCTAssertTrue(attributes.contains { $0 is OutgoingContentInfoMessageAttribute })
        XCTAssertTrue(attributes.contains { $0 is NotificationInfoMessageAttribute })
        XCTAssertTrue(stickers.isEmpty)
        XCTAssertTrue(packs.isEmpty)
        XCTAssertNil(media)
        XCTAssertNil(thread)
        XCTAssertNil(reply)
        XCTAssertNil(story)
        XCTAssertNil(grouping)
        XCTAssertNil(correlation)
        XCTAssertEqual(owner.draft, "Existing draft")
    }

    func testForumUsesThreadRootAndHidesOtherTopicAndScheduledResults() throws {
        let owner = ChatInteraction(peer: TelegramChannel(.forum), topic: true)
        let postbox = owner.interactionContext.account.postbox
        postbox.source?.threadId = 31
        XCTAssertNil(owner.menu())
        postbox.source?.threadId = 21
        try XCTUnwrap(owner.menu()).handler()
        Fixture.prompts[0].accept()
        guard case let .message(_, _, _, _, thread, reply, _, _, _, _) = try XCTUnwrap(Fixture.sent.first).1 else {
            return XCTFail("Expected text")
        }
        XCTAssertEqual(thread, 21)
        XCTAssertEqual(reply, Reply(messageId: .init(peerId: .forum, id: 21), quote: nil, innerSubject: nil))
        owner.mode = .scheduled
        XCTAssertNil(owner.menu())
    }

    func testNonOrdinaryProtectedAndPaidContentIsIneligible() {
        let owner = ChatInteraction()
        let postbox = owner.interactionContext.account.postbox
        let original = postbox.source!
        let changes: [(inout Message) -> Void] = [
            { $0.incoming = true }, { $0.author = TelegramUser(.user) }, { $0.id.namespace = 1 },
            { $0.isScheduledMessage = true }, { $0.flags = .Sending }, { $0.media = [1] },
            { $0.groupingKey = 1 }, { $0.forwardInfo = 1 }, { $0.replyMarkup = 1 },
            { $0.containsSecretMedia = true }, { $0.autoclearTimeout = 5 }, { $0.paidContent = 1 },
            { $0.protected = true }, { $0.hidden = true }, { $0.attributes = [RichTextMessageAttribute()] },
            { $0.attributes = [RestrictedContentMessageAttribute()] }, { $0.attributes = [InlineBotMessageAttribute()] }
        ]
        for change in changes {
            var candidate = original
            change(&candidate)
            postbox.source = candidate
            XCTAssertNil(owner.menu())
        }
        postbox.source = original
        owner.presentation.slowMode = 1
        XCTAssertNil(owner.menu())
        owner.presentation.slowMode = nil
        owner.presentation.sendPaidMessageStars = .init(value: 2)
        XCTAssertNil(owner.menu())
    }

    func testAfterConfirmationLocalDeletionEditAndProtectionPreventSend() throws {
        let owner = ChatInteraction()
        let postbox = owner.interactionContext.account.postbox
        let original = postbox.source!
        for update in [
            { postbox.source = nil },
            { postbox.source?.text = "Edited" },
            { postbox.peer?.isCopyProtectionEnabled = true }
        ] {
            let menu = try XCTUnwrap(owner.menu())
            menu.handler()
            update()
            Fixture.prompts.last?.accept()
            XCTAssertTrue(Fixture.sent.isEmpty)
            XCTAssertEqual(Fixture.alerts.last, "Gergram.Chat.RepeatMessageUnavailable")
            postbox.source = original
            postbox.peer?.isCopyProtectionEnabled = false
        }
        XCTAssertEqual(postbox.readCount, 3)
    }

    func testCancellationAndAccountLossKeepExistingDraftAndRejectStaleCallbacks() throws {
        let owner = ChatInteraction(peer: TelegramUser(.user))
        try XCTUnwrap(owner.menu()).handler()
        let first = Fixture.prompts[0]
        first.cancel()
        first.accept()
        XCTAssertEqual(owner.interactionContext.engine.peers.fetchCount, 0)
        let response = ValuePipe<Bool>()
        owner.interactionContext.engine.peers.refresh = response.signal()
        try XCTUnwrap(owner.menu()).handler()
        Fixture.prompts[1].accept()
        XCTAssertNil(owner.menu())
        owner.interactionContext.sharedContext.accounts.set(.init(primary: nil))
        owner.interactionContext.sharedContext.accounts.set(.init())
        response.putNext(true)
        XCTAssertTrue(Fixture.sent.isEmpty)
        XCTAssertEqual(owner.draft, "Existing draft")
        XCTAssertNotNil(owner.menu())
    }

    func testFreshPrivateDataCanBlockNewChargesAndMissingCachedProtection() throws {
        let owner = ChatInteraction(peer: TelegramUser(.user))
        let postbox = owner.interactionContext.account.postbox
        for cached: CachedPeerData? in [CachedUserData(sendPaidMessageStars: .init(value: 10)), nil] {
            try XCTUnwrap(owner.menu()).handler()
            postbox.cached = cached
            Fixture.prompts.last?.accept()
            XCTAssertTrue(Fixture.sent.isEmpty)
            XCTAssertEqual(Fixture.alerts.last, "Gergram.Chat.RepeatMessageUnavailable")
        }
        XCTAssertEqual(owner.interactionContext.engine.peers.fetchCount, 2)
    }

    func testPayloadRejectsBrokenAndUnrepresentableEntities() {
        XCTAssertNil(ChatRepeatMessagePayload(text: "  \n", entities: []))
        XCTAssertNil(ChatRepeatMessagePayload(text: String(repeating: "x", count: 4097), entities: []))
        XCTAssertNil(ChatRepeatMessagePayload(text: "😀x", entities: [.init(range: 1..<2, type: .Bold)]))
        XCTAssertNil(ChatRepeatMessagePayload(text: "😀x", entities: [.init(range: 2..<4, type: .Bold)]))
        XCTAssertNil(ChatRepeatMessagePayload(text: "😀x", entities: [.init(range: 0..<2, type: .CustomEmoji)]))
        XCTAssertNotEqual(ChatRepeatMessagePayload(text: "é", entities: []), ChatRepeatMessagePayload(text: "e\u{301}", entities: []))
        XCTAssertNotNil(ChatRepeatMessagePayload(text: "😀x", entities: [.init(range: 0..<2, type: .Spoiler), .init(range: 2..<3, type: .TextUrl("https://example.org"))]))
    }

    func testEnqueueRejectionReportsFailureWithoutAutoRetry() throws {
        let owner = ChatInteraction()
        Fixture.enqueue = .single([nil])
        try XCTUnwrap(owner.menu()).handler()
        Fixture.prompts[0].accept()
        XCTAssertEqual(Fixture.sent.count, 1)
        XCTAssertEqual(Fixture.alerts, ["Gergram.Chat.RepeatMessageFailed"])
        XCTAssertNotNil(owner.menu())
    }

    func testRepeatVisibilityParticipatesInExistingSettingsAndReset() throws {
        let suite = "Gergram.RepeatMessage.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MessageContextMenuPreferences(defaults: defaults)
        XCTAssertFalse(preferences.isVisible(.repeatMessage, extendedMenu: false))
        XCTAssertFalse(preferences.isVisible(.repeatMessage, extendedMenu: true))
        preferences.setVisibility(.extended, for: .repeatMessage)
        XCTAssertTrue(preferences.isVisible(.repeatMessage, extendedMenu: true))
        preferences.resetVisibility()
        XCTAssertEqual(preferences.visibility(for: .repeatMessage), .hidden)
    }

    func testCloudPhotoUsesFreshReferenceAndPreservesCaptionAndTopic() throws {
        let owner = ChatInteraction(peer: TelegramChannel(.forum), topic: true)
        let postbox = owner.interactionContext.account.postbox
        postbox.source?.media = [TelegramMediaImage()]
        try XCTUnwrap(owner.menu()).handler()
        postbox.source?.media = [TelegramMediaImage(reference: .cloud(10, 42, Data([9])))]
        Fixture.prompts[0].accept()
        Fixture.prompts[0].accept()
        XCTAssertEqual(Fixture.sent.count, 1)
        let sent = try XCTUnwrap(Fixture.sent.first)
        XCTAssertEqual(sent.0, .forum)
        guard case let .message(text, attributes, _, media, thread, reply, _, grouping, _, _) = sent.1,
              case let .message(reference, image) = media,
              let photo = image as? TelegramMediaImage,
              case let .cloud(_, _, bytes) = photo.reference else {
            return XCTFail("Expected a message-backed cloud photo")
        }
        XCTAssertEqual(reference.id, postbox.source?.id)
        XCTAssertEqual(bytes, Data([9]))
        XCTAssertEqual(text, "👋  formatted  ")
        XCTAssertEqual((attributes.first as? TextEntitiesMessageAttribute)?.entities, [.init(range: 4..<13, type: .Bold)])
        XCTAssertEqual(thread, 21)
        XCTAssertEqual(reply, Reply(messageId: .init(peerId: .forum, id: 21), quote: nil, innerSubject: nil))
        XCTAssertNil(grouping)
        XCTAssertEqual(owner.draft, "Existing draft")
    }

    func testCloudPhotoCanRepeatWithoutCaptionAndRespectsAccountCaptionLimit() throws {
        let owner = ChatInteraction()
        let postbox = owner.interactionContext.account.postbox
        postbox.source?.media = [TelegramMediaImage()]
        postbox.source?.textEntities = nil
        postbox.source?.text = String(repeating: "a", count: 1025)
        XCTAssertNil(owner.menu())
        owner.interactionContext.isPremium = true
        XCTAssertNotNil(owner.menu())
        postbox.source?.text = ""
        try XCTUnwrap(owner.menu()).handler()
        Fixture.prompts[0].accept()
        guard case let .message(text, _, _, media, _, _, _, _, _, _) = try XCTUnwrap(Fixture.sent.first).1 else {
            return XCTFail("Expected a cloud photo")
        }
        XCTAssertEqual(text, "")
        XCTAssertNotNil(media)
    }

    func testCloudPhotoRejectsUnsafeAttachmentsAndCurrentMediaRestriction() {
        let owner = ChatInteraction()
        let postbox = owner.interactionContext.account.postbox
        let allowed = TelegramMediaImage()
        let unsupported: [[Any]] = [
            [allowed, allowed],
            [TelegramMediaImage(reference: nil)],
            [TelegramMediaImage(reference: .cloud(10, 42, nil))],
            [TelegramMediaImage(reference: .cloud(10, 42, Data()))],
            [TelegramMediaImage(reference: .cloud(11, 42, Data([1])))],
            [TelegramMediaImage(imageId: .init(namespace: 0, id: 10))],
            [TelegramMediaImage(representations: [.init(resource: 1)])],
            [TelegramMediaImage(video: 1)],
            [TelegramMediaImage(videoRepresentations: [1])],
            [TelegramMediaImage(emojiMarkup: 1)]
        ]
        for attachments in unsupported {
            postbox.source?.media = attachments
            XCTAssertNil(owner.menu())
        }
        postbox.source?.media = [allowed]
        let valid = postbox.source!
        let changes: [(inout Message) -> Void] = [
            { $0.isMediaSpoilered = true }, { $0.sensitive = true },
            { $0.autoremoveAttribute = 1 }, { $0.groupingKey = 1 },
            { $0.hasMessageReference = false }, { $0.protected = true }
        ]
        for change in changes {
            var message = valid
            change(&message)
            postbox.source = message
            XCTAssertNil(owner.menu())
        }
        postbox.source = valid
        owner.peer?.bannedPhoto = true
        XCTAssertNil(owner.menu())
        owner.peer?.bannedPhoto = false
        owner.peer?.canSendPhoto = false
        XCTAssertNil(owner.menu())
    }

    func testCloudPhotoRechecksIdentityAndPermissionAfterConfirmation() throws {
        let owner = ChatInteraction()
        let postbox = owner.interactionContext.account.postbox
        postbox.source?.media = [TelegramMediaImage()]
        try XCTUnwrap(owner.menu()).handler()
        postbox.source?.media = [TelegramMediaImage(imageId: .init(id: 11), reference: .cloud(11, 42, Data([1])))]
        Fixture.prompts[0].accept()
        XCTAssertEqual(Fixture.alerts, ["Gergram.Chat.RepeatMessageUnavailable"])
        XCTAssertTrue(Fixture.sent.isEmpty)

        postbox.source?.media = [TelegramMediaImage()]
        try XCTUnwrap(owner.menu()).handler()
        let freshPeer = TelegramGroup(.group)
        freshPeer.bannedPhoto = true
        postbox.peer = freshPeer
        Fixture.prompts[1].accept()
        XCTAssertTrue(Fixture.sent.isEmpty)
        XCTAssertEqual(Fixture.alerts.count, 2)
    }
}

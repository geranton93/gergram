import Foundation
import SwiftSignalKit
import XCTest

struct TelegramMediaFile {
    var isSticker = false
    var isAnimatedSticker = false
    var isVideoSticker = false
    var isInstantVideo = false
    var isVoice = false
    var isMusic = false
    var isAnimated = true
    var mimeType = "video/mp4"
}

enum ChatContextResult {
    enum Message { case auto, text, widget }
    struct External { let type: String; let message: Message; let content: Bool? }
    struct Internal { let type: String; let message: Message; let file: TelegramMediaFile? }
    case externalReference(External)
    case internalReference(Internal)
    var type: String {
        switch self {
        case let .externalReference(value): return value.type
        case let .internalReference(value): return value.type
        }
    }
    var message: Message {
        switch self {
        case let .externalReference(value): return value.message
        case let .internalReference(value): return value.message
        }
    }
    static let gif = Self.externalReference(.init(type: "gif", message: .auto, content: true))
}

struct ChatContextResultCollection { var botId = 2 }
struct ChatMediaSendConfirmationPreferences {
    enum Kind { case gif }
    static var shared = Self()
    var enabled = true
    func isEnabled(for kind: Kind) -> Bool { enabled }
}
enum Mode: Equatable {
    case history, thread, scheduled, customChatContents, pinned, customLink, preview
    var isThreadMode: Bool { self == .thread }
}
enum Sound { case automatic, silent }
enum ChatState { case normal, editing }
typealias PeerId = Int
enum Rights: Hashable { case banSendGifs, banSendInline }
struct ThreadInfo { var isClosed = false; var isOwnedByMe = false }
struct SlowMode { var hasLocked = false }
struct Stars: Equatable { var value: Int64 }
struct StarsState { var balance: Stars }
struct Peer {
    var id = 1
    var isAdmin = false
    var banned: Set<Rights> = []
    var canSend = true
    var displayTitle: String { "Peer" }
    func canSendMessage(_ isThreadMode: Bool, threadData: ThreadInfo?, cachedData: Int?) -> Bool { canSend }
}
func permissionText(from peer: Peer, for right: Rights, cachedData: Int?) -> String? {
    peer.banned.contains(right) ? "Restricted" : nil
}
struct Presentation {
    var state = ChatState.normal
    var isNotAccessible = false
    var isBlocked: Bool?
    var slowMode: SlowMode?
    var slowModeMultipleLocked = false
    var threadInfo: ThreadInfo?
    var sendPaidMessageStars: Stars?
    var starsState: StarsState?
    var alwaysPaidMessage = false
    var peer: Peer? = Peer()
    var cachedData: Int?
    func withUpdatedAlwaysPaidMessage(_ value: Bool) -> Self {
        var copy = self
        copy.alwaysPaidMessage = value
        return copy
    }
}
final class ChatInteraction {
    var sendInlineResult: (ChatContextResultCollection, ChatContextResult) -> Void = { _, _ in }
    var mode = Mode.history
    var presentation = Presentation()
    var peer: Peer? { presentation.peer }
    var revision = 0
    var text = "Inline query"
    var animated = true
    var sound = Sound.silent
    var interactionContext: Context
    init(context: Context) { interactionContext = context }
    func canAnimateUpdates() -> Bool { animated }
    func captureDeferredSendAction() -> ChatDeferredSendAction {
        let revision = self.revision
        return ChatDeferredSendAction { [weak self] in self?.revision == revision }
    }
    func captureAnalyticsContext() -> AnalyticsContext { AnalyticsContext() }
    func resolvedSendSound() -> Sound { sound }
    func update(_ update: (Presentation) -> Presentation) { presentation = update(presentation) }
__POLICY__
}

final class Window {
    var isVisible = true
    let visibilityState = ValuePromise(true, ignoreRepeated: true)
    var visibility: Signal<Bool, NoError> { visibilityState.get() }
}
struct Account: Equatable { var id = 10 }
struct Accounts: Equatable { var primary: Account? = Account() }
final class SharedContext {
    let value = ValuePromise(Accounts())
    var activeAccounts: Signal<Accounts, NoError> { value.get() }
}
final class Context {
    var isCurrent = true
    var isExternal = false
    var isFrozen = false
    let sharedContext = SharedContext()
    let window = Window()
    let account = Account()
    let engine = Engine()
}
final class Engine { let messages = EngineMessages() }
struct Enqueued: Equatable {
    let peerId: Int
    let threadId: Int64?
    let botId: Int
    let resultType: String
    let reply: Int?
    let silent: Bool
    let date: Int32?
    let payment: Stars?
}
struct EngineMessages {
    func outgoingMessageWithChatContextResult(to peerId: Int, threadId: Int64?, botId: Int, result: ChatContextResult, replyToMessageId: Int?, replyToStoryId: Int?, hideVia: Bool, silentPosting: Bool, scheduleTime: Int32?, sendPaidMessageStars: Stars?, postpone: Bool, correlationId: Int64?) -> Enqueued? {
        Enqueued(peerId: peerId, threadId: threadId, botId: botId, resultType: result.type, reply: replyToMessageId, silent: silentPosting, date: scheduleTime, payment: sendPaidMessageStars)
    }
}
enum Delivery { static var messages: [Enqueued] = [] }
func enqueueMessages(account: Account, peerId: Int, messages: [Enqueued]) -> Signal<[Int?], NoError> {
    Delivery.messages += messages
    return .single([1])
}
final class AnalyticsPresentation { func end() {} }
struct AnalyticsContext {
    func restricting(peerId: Int) -> Self { self }
    func beginPresentation() -> AnalyticsPresentation { AnalyticsPresentation() }
    func preservingPresentation<Value>(_ signal: Signal<Value, NoError>) -> Signal<Value, NoError> { signal }
}
struct Analytics {
    static let shared = Self()
    func unresolvedContext() -> AnalyticsContext { AnalyticsContext() }
    func captureContext(engine: Engine, peerId: Int, inherited: AnalyticsContext) -> AnalyticsContext { inherited }
}
struct Observation {
    func complete(expectedCount: Int, resultCount: Int, acceptedCount: Int) {}
}
func chatAnalyticsMessageKind(_ result: ChatContextResult) -> String { result.type }
final class Transaction {
    var handler: (() -> Void)?
    func set(handler: @escaping () -> Void) { self.handler = handler }
}

struct Prompt {
    let accept: () -> Void
    let cancel: () -> Void
    let dismiss: () -> Void
}
struct PaymentPrompt {
    let accept: (ConfirmResult) -> Void
    let cancel: () -> Void
    let dismiss: () -> Void
}
struct DatePrompt {
    let select: (Date, Int32?) -> Void
    let cancel: () -> Void
    let dismiss: () -> Void
}
enum Prompts {
    static var confirmations: [Prompt] = []
    static var payments: [PaymentPrompt] = []
    static var dates: [DatePrompt] = []
    static var purchases = 0
    static var paidPreferenceWrites = 0
}
struct ModalAlertData {
    enum Mode { case confirm(text: String, isThird: Bool) }
    let title: String
    let info: String
    let ok: String
    let mode: Mode
}
func showDismissableModalAlert(for window: Window, data: ModalAlertData, completion: @escaping (Bool) -> Void, cancel: @escaping () -> Void, onDeinit: @escaping () -> Void) -> () -> Void {
    Prompts.confirmations.append(Prompt(accept: { completion(true) }, cancel: cancel, dismiss: onDeinit))
    return onDeinit
}
func localizedString(_ key: String) -> String { key }
struct Strings {
    let modalSend = "Send"
    let modalCancel = "Cancel"
    let chatPayStarsConfirmTitle = "Payment"
    let chatPayStarsConfirmCheckbox = "Remember"
    func starListItemCountOther(_ count: Int) -> String { "\(count)" }
    func chatPayStarsConfirmMessagesOther(_ count: Int) -> String { "\(count)" }
    func chatPayStarsConfirmText(_ peer: String, _ amount: String, _ total: String, _ count: String) -> String { peer }
    func chatPayStarsConfirmPayOther(_ count: Int) -> String { "\(count)" }
}
func strings() -> Strings { Strings() }
enum ConfirmResult { case basic, thrid }
func verifyChatSendPayment(for window: Window, header: String, information: String, ok: String, option: String, analyticsContext: AnalyticsContext, successHandler: @escaping (ConfirmResult) -> Void, cancelHandler: @escaping () -> Void = {}, dismissed: @escaping () -> Void = {}) {
    Prompts.payments.append(.init(accept: successHandler, cancel: cancelHandler, dismiss: dismissed))
}
func chatPaidMessagePriceIsCurrent(_ interaction: ChatInteraction, _ price: Stars) -> Bool {
    interaction.presentation.sendPaidMessageStars == price
}
struct FastSettings {
    static func toggleCofirmPaid(_ peerId: Int, price: Int) { Prompts.paidPreferenceWrites += 1 }
}
enum DateMode { case schedule(Int) }
enum Currency { case stars }
struct FeatureNavigationHooks {
    static let shared = Self()
    func selectDateObserved(_ context: Context, _ window: Window, _ date: Date?, _ period: Int32?, _ mode: DateMode, analyticsContext: AnalyticsContext, selectedAt: @escaping (Date, Int32?) -> Void, cancelled: @escaping () -> Void, dismissed: @escaping () -> Void) {
        Prompts.dates.append(.init(select: selectedAt, cancel: cancelled, dismiss: dismissed))
    }
    func showStarsPurchaseWithContext(_ context: Context, _ window: Window, _ currency: Currency, _ purpose: String?, _ amount: Int64, _ analyticsContext: AnalyticsContext) {
        Prompts.purchases += 1
    }
}
func chatDateSelector(context: Context, mode: DateMode, analyticsContext: AnalyticsContext, selectedAt: @escaping (Date, Int32?) -> Void) -> DatePrompt {
    .init(select: selectedAt, cancel: {}, dismiss: {})
}
func showModal(with controller: DatePrompt, for window: Window) { Prompts.dates.append(controller) }

final class ChatController {
    let context = Context()
    let mediaSendConfirmation = ChatMediaSendConfirmation()
    let inlineGifSend = ChatInlineGifSend()
    let nextTransaction = Transaction()
    lazy var chatInteraction = ChatInteraction(context: context)
    var mode: Mode { chatInteraction.mode }
    var threadId: Int64? = 42
    var reply = 123
    func configure() {
        let chatInteraction = self.chatInteraction
        let context = self.context
        let makePeerId = { [weak self] in self?.chatInteraction.peer?.id ?? 1 }
        let threadId64 = { [weak self] in self?.threadId }
        let takeReplyId = { [weak self] in self?.reply }
        let takePaidMessageStars = { [weak self] in self?.chatInteraction.presentation.sendPaidMessageStars }
        let afterSentTransition: () -> Void = { [weak chatInteraction] in chatInteraction?.text = "" }
__SEND__
    }
__CONFIRM__
    func makeMessageSendObservation(_ kind: String, analyticsContext: AnalyticsContext, scheduled: Bool, silent: Bool) -> Observation? { Observation() }
    func select(_ result: ChatContextResult = .gif) { chatInteraction.sendInlineResult(.init(), result) }
    func withPayment(price: Int64 = 4, balance: Int64 = 20) {
        chatInteraction.presentation.sendPaidMessageStars = Stars(value: price)
        chatInteraction.presentation.starsState = StarsState(balance: Stars(value: balance))
    }
}

final class InlineGifTests: XCTestCase {
    private let scheduled = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        ChatMediaSendConfirmationPreferences.shared.enabled = true
        Delivery.messages = []
        Prompts.confirmations = []
        Prompts.payments = []
        Prompts.dates = []
        Prompts.purchases = 0
        Prompts.paidPreferenceWrites = 0
    }

    func testOnlyActualGifMediaRequestsConfirmation() {
        let controller = ChatController()
        controller.configure()
        let gif = ChatContextResult.internalReference(.init(type: "gif", message: .auto, file: .init()))
        let rawGif = ChatContextResult.internalReference(.init(type: "gif", message: .auto, file: .init(isAnimated: false, mimeType: "image/gif")))
        XCTAssertTrue(controller.chatInteraction.shouldDeferInlineResultSendFlight(gif))
        XCTAssertTrue(controller.chatInteraction.shouldDeferInlineResultSendFlight(rawGif))
        XCTAssertTrue(controller.chatInteraction.shouldDeferInlineResultSendFlight(.externalReference(.init(type: "gif", message: .auto, content: nil))))
        for result in [
            .externalReference(.init(type: "photo", message: .auto, content: true)),
            .externalReference(.init(type: "gif", message: .text, content: true)),
            .externalReference(.init(type: "gif", message: .widget, content: true)),
            .internalReference(.init(type: "gif", message: .auto, file: nil)),
            .internalReference(.init(type: "gif", message: .auto, file: .init(isSticker: true))),
            .internalReference(.init(type: "gif", message: .auto, file: .init(isAnimated: false)))
        ] as [ChatContextResult] {
            XCTAssertFalse(controller.chatInteraction.shouldDeferInlineResultSendFlight(result))
            controller.select(result)
        }
        XCTAssertEqual(Prompts.confirmations.count, 0)
        XCTAssertEqual(Delivery.messages.count, 6)
    }

    func testDefaultOffAndCustomChatUseNativeImmediatePath() {
        let controller = ChatController()
        controller.configure()
        ChatMediaSendConfirmationPreferences.shared.enabled = false
        controller.select()
        ChatMediaSendConfirmationPreferences.shared.enabled = true
        controller.chatInteraction.mode = .customChatContents
        controller.select()
        XCTAssertEqual(Prompts.confirmations.count, 0)
        XCTAssertEqual(Delivery.messages.count, 2)
    }

    func testCancelAndDuplicateCallbacksPreserveDraftUntilAcceptedEnqueue() {
        let controller = ChatController()
        controller.configure()
        controller.select()
        controller.select()
        XCTAssertEqual(Prompts.confirmations.count, 1)
        let cancelled = Prompts.confirmations[0]
        cancelled.cancel()
        cancelled.accept()
        XCTAssertEqual(controller.chatInteraction.text, "Inline query")
        XCTAssertNil(controller.nextTransaction.handler)
        XCTAssertTrue(Delivery.messages.isEmpty)

        controller.select()
        let accepted = Prompts.confirmations[1]
        accepted.accept()
        accepted.accept()
        XCTAssertEqual(Delivery.messages, [.init(peerId: 1, threadId: 42, botId: 2, resultType: "gif", reply: 123, silent: true, date: nil, payment: nil)])
        XCTAssertNotNil(controller.nextTransaction.handler)
    }

    func testScheduledSendRetainsAttemptUntilOneDateAndPreservesPaidQuote() {
        let controller = ChatController()
        controller.configure()
        controller.chatInteraction.mode = .scheduled
        controller.withPayment()
        controller.select()
        Prompts.confirmations[0].accept()
        XCTAssertEqual(Prompts.payments.count, 1)
        XCTAssertTrue(Delivery.messages.isEmpty)
        controller.select()
        XCTAssertEqual(Prompts.confirmations.count, 1)
        Prompts.payments[0].accept(.thrid)
        Prompts.payments[0].accept(.thrid)
        XCTAssertEqual(Prompts.paidPreferenceWrites, 1)
        XCTAssertEqual(Prompts.dates.count, 1)
        controller.select()
        XCTAssertEqual(Prompts.confirmations.count, 1)
        XCTAssertTrue(Delivery.messages.isEmpty)
        let prompt = Prompts.dates[0]
        prompt.select(scheduled, nil)
        prompt.select(scheduled, nil)
        prompt.dismiss()
        XCTAssertEqual(Delivery.messages, [.init(peerId: 1, threadId: 42, botId: 2, resultType: "gif", reply: 123, silent: true, date: Int32(scheduled.timeIntervalSince1970), payment: Stars(value: 4))])
    }

    func testStaleDraftThreadPermissionsAccountAndWindowNeverEnqueue() {
        let changes: [(ChatController) -> Void] = [
            { $0.chatInteraction.revision += 1 },
            { $0.threadId = 5 },
            { $0.chatInteraction.presentation.peer?.banned.insert(.banSendGifs) },
            { $0.chatInteraction.presentation.peer?.banned.insert(.banSendInline) },
            { $0.chatInteraction.presentation.threadInfo = ThreadInfo(isClosed: true) },
            { $0.chatInteraction.presentation.slowMode = SlowMode(hasLocked: true) },
            { $0.context.isCurrent = false; $0.context.sharedContext.value.set(Accounts(primary: nil)) },
            { $0.context.window.isVisible = false; $0.context.window.visibilityState.set(false) }
        ]
        for change in changes {
            let controller = ChatController()
            controller.configure()
            controller.select()
            let prompt = Prompts.confirmations.last!
            change(controller)
            prompt.accept()
            XCTAssertTrue(Delivery.messages.isEmpty)
            XCTAssertFalse(controller.inlineGifSend.isPending)
        }
    }

    func testPaymentCancelAndStaleDateCanRetryWithoutEnqueuing() {
        let controller = ChatController()
        controller.configure()
        controller.chatInteraction.mode = .scheduled
        controller.withPayment()
        controller.select()
        Prompts.confirmations[0].accept()
        Prompts.payments[0].cancel()
        Prompts.payments[0].accept(.thrid)
        XCTAssertFalse(controller.inlineGifSend.isPending)
        XCTAssertTrue(Prompts.dates.isEmpty)
        XCTAssertEqual(Prompts.paidPreferenceWrites, 0)

        controller.select()
        Prompts.confirmations[1].accept()
        Prompts.payments[1].accept(.basic)
        let old = Prompts.dates[0]
        old.cancel()
        controller.select()
        Prompts.confirmations[2].accept()
        Prompts.payments[2].accept(.basic)
        old.select(scheduled, nil)
        XCTAssertTrue(controller.inlineGifSend.isPending)
        controller.chatInteraction.presentation.sendPaidMessageStars = Stars(value: 9)
        Prompts.dates[1].select(scheduled, nil)
        XCTAssertTrue(Delivery.messages.isEmpty)
        XCTAssertFalse(controller.inlineGifSend.isPending)
    }

    func testPaymentUsesLiveBalanceAndRetainedCallbacksDoNotKeepOwnerAlive() {
        var controller: ChatController? = ChatController()
        weak var owner = controller
        controller?.configure()
        controller?.withPayment()
        controller?.select()
        Prompts.confirmations[0].accept()
        controller?.withPayment(balance: 1)
        Prompts.payments[0].accept(.thrid)
        XCTAssertEqual(Prompts.purchases, 1)
        XCTAssertEqual(Prompts.paidPreferenceWrites, 0)
        XCTAssertTrue(Delivery.messages.isEmpty)

        controller?.select()
        Prompts.confirmations[1].accept()
        controller = nil
        XCTAssertNil(owner)
        Prompts.payments[1].accept(.basic)
        XCTAssertTrue(Delivery.messages.isEmpty)
    }

    func testAccountAndWindowLossInvalidateAcceptedRequestsEvenAfterRestoration() {
        let controller = ChatController()
        controller.configure()
        controller.chatInteraction.mode = .scheduled
        controller.withPayment()
        controller.select()
        Prompts.confirmations[0].accept()
        controller.context.sharedContext.value.set(Accounts(primary: nil))
        controller.context.sharedContext.value.set(Accounts())
        Prompts.payments[0].accept(.thrid)
        XCTAssertFalse(controller.inlineGifSend.isPending)
        XCTAssertEqual(Prompts.paidPreferenceWrites, 0)

        controller.select()
        Prompts.confirmations[1].accept()
        Prompts.payments[1].accept(.basic)
        controller.context.window.visibilityState.set(false)
        controller.context.window.visibilityState.set(true)
        Prompts.dates[0].select(scheduled, nil)
        XCTAssertFalse(controller.inlineGifSend.isPending)
        XCTAssertTrue(Delivery.messages.isEmpty)
    }
}

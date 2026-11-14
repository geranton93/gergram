import AppKit
import SwiftSignalKit
import XCTest

typealias PeerId = Int
class Peer {}
final class TelegramUser: Peer {
    let id: PeerId
    var isBot = false
    var isDeleted = false
    init(_ id: PeerId) { self.id = id }
}
struct CachedUserData {
    enum GiftOptions { case All, some }
    var disallowedGifts: GiftOptions = .some
}
struct ChatPresentationInterfaceState {
    enum Mode { case history, thread, scheduled }
    struct SearchMode { var inSearch = false }
    struct Input { var inputText = "" }
    struct Location { var peerId = 2 }
    var hasGift = true
    var effectiveInput = Input()
    var chatMode = Mode.history
    var chatLocation = Location()
    var searchMode = SearchMode()
    var isNotAccessible = false
    var peer: Peer? = TelegramUser(2)
    var cachedData: Any? = CachedUserData()
}
final class InteractionContext { let peerId = 1 }
final class ChatInteraction {
    var presentation = ChatPresentationInterfaceState()
    let interactionContext = InteractionContext()
}
final class Layer {
    var opacity: Float = 1
    func presentation() -> Layer? { self }
    func value(forKeyPath path: String) -> Any? { CGFloat(1) }
    func animateScaleSpring(from: CGFloat, to: CGFloat, duration: Double, bounce: Bool) {}
}
class View {
    var isHidden = false
    var frame = NSRect(x: 0, y: 0, width: 40, height: 40)
}
typealias NSView = View
final class ImageButton: View {
    let layer: Layer? = Layer()
    var controlIsHidden: Bool { isHidden || (layer?.opacity ?? 1) < 0.5 }
    var superview: Int? = 1
    func change(opacity: CGFloat, animated: Bool, completion: (Bool) -> Void) {
        layer?.opacity = Float(opacity)
        completion(true)
    }
}
enum ContainedViewLayoutTransition {
    case immediate
    func updateFrame(view: ImageButton, frame: NSRect) { view.frame = frame }
}
final class ChatInputActionsView {
    let chatInteraction = ChatInteraction()
    let giftButtonPreferenceDisposable = MetaDisposable()
    var actionVisibilityChanged: (() -> Void)?
    let frame = NSRect(x: 0, y: 0, width: 300, height: 40)
    let window: Int? = 1
    let gift = ImageButton()
    let keyboard = ImageButton()
    let muteChannelMessages = ImageButton()
    let suggestPost = ImageButton()
    let entertaiments = ImageButton()
    let scheduled: ImageButton? = nil
    let secretTimer: ImageButton? = nil

    init() {
        keyboard.isHidden = true
        muteChannelMessages.isHidden = true
        suggestPost.isHidden = true
    }
    func addSubview(_ view: ImageButton) { view.superview = 1 }
    func bind() {
__BIND__
    }
__UPDATE__
__BUTTONS__
    deinit { giftButtonPreferenceDisposable.dispose() }
}

final class ComposerGiftButtonTests: XCTestCase {
    override func setUp() { ComposerGiftButtonPreferences.shared.setHidden(false) }
    override func tearDown() { ComposerGiftButtonPreferences.shared.setHidden(false) }

    func testDefaultVisiblePreferencePersistsAndDeduplicates() throws {
        let name = "Gergram.GiftButtonTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = ComposerGiftButtonPreferences(defaults: defaults)
        var values: [Bool] = []
        let observation = preferences.signal.start(next: { values.append($0) })
        defer { observation.dispose() }
        XCTAssertFalse(preferences.hidesButton)
        preferences.setHidden(true)
        preferences.setHidden(true)
        XCTAssertTrue(ComposerGiftButtonPreferences(defaults: defaults).hidesButton)
        preferences.setHidden(false)
        XCTAssertEqual(values, [false, true, false])
    }

    func testOrdinaryRecipientButtonReleasesSlotAndRestoresLive() {
        let view = ChatInputActionsView()
        var heightUpdates = 0
        view.actionVisibilityChanged = { heightUpdates += 1 }
        view.bind()
        XCTAssertEqual(view.visibleWidth, 80)
        ComposerGiftButtonPreferences.shared.setHidden(true)
        XCTAssertTrue(view.gift.controlIsHidden)
        XCTAssertEqual(view.visibleWidth, 40)
        ComposerGiftButtonPreferences.shared.setHidden(false)
        XCTAssertFalse(view.gift.controlIsHidden)
        XCTAssertEqual(view.visibleWidth, 80)
        XCTAssertEqual(heightUpdates, 2)
    }

    func testKeepsButtonWhenProfileGiftActionIsUnavailable() {
        var selfChat = ChatPresentationInterfaceState()
        selfChat.peer = TelegramUser(1)
        selfChat.chatLocation.peerId = 1
        var hiddenGifts = ChatPresentationInterfaceState()
        hiddenGifts.cachedData = CachedUserData(disallowedGifts: .All)
        var missingData = ChatPresentationInterfaceState()
        missingData.cachedData = nil
        var deleted = ChatPresentationInterfaceState()
        (deleted.peer as? TelegramUser)?.isDeleted = true
        var bot = ChatPresentationInterfaceState()
        (bot.peer as? TelegramUser)?.isBot = true
        var differentPeer = ChatPresentationInterfaceState()
        differentPeer.chatLocation.peerId = 3
        var threaded = ChatPresentationInterfaceState()
        threaded.chatMode = .thread
        var searching = ChatPresentationInterfaceState()
        searching.searchMode.inSearch = true
        var inaccessible = ChatPresentationInterfaceState()
        inaccessible.isNotAccessible = true
        for state in [selfChat, hiddenGifts, missingData, deleted, bot, differentPeer, threaded, searching, inaccessible] {
            XCTAssertTrue(state.showsComposerGiftButton(hidesGiftButton: true, accountPeerId: 1))
        }
    }

    func testNativeUnavailableOrDraftNeverGainsAButton() {
        var state = ChatPresentationInterfaceState()
        XCTAssertTrue(state.showsComposerGiftButton(hidesGiftButton: false, accountPeerId: 1))
        XCTAssertFalse(state.showsComposerGiftButton(hidesGiftButton: true, accountPeerId: 1))
        state.hasGift = false
        XCTAssertFalse(state.showsComposerGiftButton(hidesGiftButton: false, accountPeerId: 1))
        state.hasGift = true
        state.effectiveInput.inputText = "Hello"
        XCTAssertFalse(state.showsComposerGiftButton(hidesGiftButton: false, accountPeerId: 1))
    }

    func testInitialHiddenSettingAndObserverDoNotRetainTheView() {
        ComposerGiftButtonPreferences.shared.setHidden(true)
        var view: ChatInputActionsView? = ChatInputActionsView()
        weak var previous = view
        view?.bind()
        XCTAssertEqual(view?.visibleWidth, 40)
        view = nil
        XCTAssertNil(previous)
        ComposerGiftButtonPreferences.shared.setHidden(false)
    }
}

import AppKit
import Foundation
import SwiftSignalKit
import XCTest

private enum ChatMode { case history, thread, preview }
private enum ChatLocation { case peer(Int), thread(Int) }
private enum ChatState { case normal, editing }
private struct SearchMode { var inSearch = false }
private struct InterfaceState { var messageEffect: Int? }
private struct Timeout { let effectiveValue: Int }
private struct MessageTimeout { let timeout: Timeout? }
private struct Flags: OptionSet {
    let rawValue: Int
    static let hasForum = Flags(rawValue: 1)
}
private struct BotInfo { let flags: Flags }
private class Peer {
    let id: Int
    var canManageDestructTimer = true
    var isSecretChat = false
    var isMonoForum = false
    var isService = false
    var restricted = false
    init(id: Int) { self.id = id }
    func restrictionText(_ contentSettings: Int) -> String? { restricted ? "Restricted" : nil }
}
private final class TelegramUser: Peer { var botInfo: BotInfo? }
private func isServicePeer(_ peer: Peer) -> Bool { peer.isService }
private struct ChatPresentationInterfaceState {
    var chatMode = ChatMode.history
    var chatLocation = ChatLocation.peer(5)
    var state = ChatState.normal
    var selectionState: Int?
    var reportMode: Int?
    var searchMode = SearchMode()
    var isNotAccessible = false
    var peer: Peer? = TelegramUser(id: 5)
    var mainPeer: Peer? { peer }
    var sendPaidMessageStars: Int?
    var interfaceState = InterfaceState()
    var hasSetDestructiveTimer = true
    var messageSecretTimeout: MessageTimeout? = .init(timeout: .init(effectiveValue: 60))
}
private final class AccountContext {
    var isFrozen = false
    let peerId = 7
    let contentSettings = 0
}
private final class ChatInteraction {
    let interactionContext = AccountContext()
    var presentation = ChatPresentationInterfaceState()
    var isLogInteraction = false
    var isGlobalSearchMessage = false
    private(set) var openedSetups = 0
    func showDeleterSetup(_ control: ImageButton) { openedSetups += 1 }
}
private struct Strings {
    let voiceOverSelfDestructTimerOff = "Timer Off"
    func voiceOverSelfDestructTimerOn(_ interval: String) -> String { "Timer On: \(interval)" }
}
private func strings() -> Strings { Strings() }
private func shortTimeIntervalString(value: Int) -> String { "\(value)" }

private final class ContextMenu {
    private(set) var count = 0
    func addItem(_ item: Int) { count += 1 }
}
private class ImageButton: NSView {
    enum Normal { case Normal }
    enum Event { case Click }
    struct ImageView { var animates = false }
    var imageView = ImageView()
    var contextMenu: (() -> ContextMenu)?
    var handler: ((ImageButton) -> Void)?
    var controlIsHidden: Bool { isHidden }
    func set(image: Int, for: Normal) {}
    func sizeToFit(_ minimum: NSSize, _ maximum: NSSize, thatFit: Bool) -> Bool { true }
    private(set) var handlerResets = 0
    func removeAllHandlers() {
        handlerResets += 1
        handler = nil
    }
    func set(handler: @escaping (ImageButton) -> Void, for event: Event) { self.handler = handler }
}
private final class ChatAccessibleImageButton: ImageButton { var accessibilityLabelProvider: (() -> String?)? }
private enum ContainedViewLayoutTransition { case immediate }
private struct Theme {
    struct Icons { let chatSecretTimer = 1 }
    let icons = Icons()
}
private let theme = Theme()
private func performSubviewRemoval(_ view: ImageButton, animated: Bool, scale: Bool) { view.removeFromSuperview() }

private final class ChatInputActionsView: NSView {
    __ROUTE__

    let chatInteraction = ChatInteraction()
    let autoDeleteButtonPreferenceDisposable = MetaDisposable()
    var actionVisibilityChanged: (() -> Void)?
    private(set) var secretTimer: ImageButton?
    private var secretTimerImageKey: String?
    private var autoDeleteButtonRoute: AutoDeleteButtonRoute?
    private static let extraButtonSize: CGFloat = 40
    let keyboard = ImageButton()
    let muteChannelMessages = ImageButton()
    let gift = ImageButton()
    let suggestPost = ImageButton()
    let scheduled: ImageButton? = nil
    let entertaiments = ImageButton(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
    private(set) var layoutUpdates = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        for button in [keyboard, muteChannelMessages, gift, suggestPost] { button.isHidden = true }
        __BIND__
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { autoDeleteButtonPreferenceDisposable.dispose() }

    __UPDATE__
    __WIDTH__

    func refresh() {
        _ = updateAutoDeleteButton(chatInteraction.presentation, hidesButton: ComposerAutoDeleteButtonPreferences.shared.hidesButton, animated: false)
    }

    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) { layoutUpdates += 1 }
    func updateSecretTimerImage(_ value: ChatPresentationInterfaceState) {}
    func secretTimerItems() -> [Int] { [1, 2] }
}

final class ComposerAutoDeleteTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ComposerAutoDeleteButtonPreferences.shared.setHidden(false)
    }

    override func tearDown() {
        ComposerAutoDeleteButtonPreferences.shared.setHidden(false)
        super.tearDown()
    }

    func testPreferencePersistsAndPublishes() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ComposerAutoDeleteButtonPreferences(defaults: defaults)
        var values: [Bool] = []
        let listener = preferences.signal.start(next: { values.append($0) })
        defer { listener.dispose() }
        XCTAssertFalse(preferences.hidesButton)
        preferences.setHidden(true)
        preferences.setHidden(true)
        XCTAssertTrue(ComposerAutoDeleteButtonPreferences(defaults: defaults).hidesButton)
        preferences.setHidden(false)
        XCTAssertEqual(values, [false, true, false])
    }

    func testLivePreferenceHidesEligibleButtonAndRestoresWidthAndAction() throws {
        let view = ChatInputActionsView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        let oldButton = try XCTUnwrap(view.secretTimer)
        XCTAssertEqual(view.visibleWidth, 80)
        oldButton.handler?(oldButton)
        XCTAssertEqual(view.chatInteraction.openedSetups, 1)
        let before = view.layoutUpdates
        var hostUpdates = 0
        view.actionVisibilityChanged = { hostUpdates += 1 }
        ComposerAutoDeleteButtonPreferences.shared.setHidden(true)
        XCTAssertNil(view.secretTimer)
        XCTAssertNil(oldButton.superview)
        XCTAssertEqual(view.visibleWidth, 40)
        XCTAssertEqual(view.layoutUpdates, before + 1)
        ComposerAutoDeleteButtonPreferences.shared.setHidden(false)
        XCTAssertEqual(view.visibleWidth, 80)
        XCTAssertEqual(view.layoutUpdates, before + 2)
        XCTAssertEqual(hostUpdates, 2)
        let button = try XCTUnwrap(view.secretTimer)
        button.handler?(button)
        XCTAssertEqual(view.chatInteraction.openedSetups, 2)
    }

    func testSecretTimerAndReadOnlyIndicatorStayReachable() throws {
        let view = ChatInputActionsView(frame: .zero)
        ComposerAutoDeleteButtonPreferences.shared.setHidden(true)
        let peer = try XCTUnwrap(view.chatInteraction.presentation.peer)
        peer.isSecretChat = true
        view.refresh()
        let button = try XCTUnwrap(view.secretTimer)
        XCTAssertEqual(button.contextMenu?().count, 2)
        XCTAssertNil(button.handler)
        XCTAssertEqual((button as? ChatAccessibleImageButton)?.accessibilityLabelProvider?(), "Timer On: 60")
        peer.isSecretChat = false
        peer.canManageDestructTimer = false
        view.refresh()
        XCTAssertTrue(view.secretTimer === button)
        XCTAssertNil(button.contextMenu)
        button.handler?(button)
        XCTAssertEqual(view.chatInteraction.openedSetups, 1)
        let resets = button.handlerResets
        view.refresh()
        XCTAssertEqual(button.handlerResets, resets)
        view.chatInteraction.presentation.peer = nil
        view.refresh()
        XCTAssertTrue(view.secretTimer === button)
        XCTAssertNil(button.handler)
        XCTAssertNil(button.contextMenu)
    }

    func testRestrictionAndHeaderFallbackCasesKeepExistingTimer() {
        let scenarios: [(ChatInteraction) -> Void] = [
            { $0.presentation.chatMode = .thread },
            { $0.presentation.chatLocation = .thread(5) },
            { $0.presentation.chatMode = .preview },
            { $0.presentation.state = .editing },
            { $0.presentation.selectionState = 1 },
            { $0.presentation.reportMode = 1 },
            { $0.presentation.searchMode.inSearch = true },
            { $0.presentation.isNotAccessible = true },
            { $0.interactionContext.isFrozen = true },
            { $0.isLogInteraction = true },
            { $0.isGlobalSearchMessage = true },
            { $0.presentation.chatLocation = .peer(7); $0.presentation.peer = Peer(id: 7) },
            { $0.presentation.peer = nil },
            { $0.presentation.peer?.isMonoForum = true },
            { $0.presentation.peer?.isService = true },
            { $0.presentation.peer?.restricted = true },
            { $0.presentation.sendPaidMessageStars = 1 },
            { ($0.presentation.peer as? TelegramUser)?.botInfo = .init(flags: .hasForum) },
        ]
        ComposerAutoDeleteButtonPreferences.shared.setHidden(true)
        for (index, apply) in scenarios.enumerated() {
            let view = ChatInputActionsView(frame: .zero)
            XCTAssertNil(view.secretTimer)
            apply(view.chatInteraction)
            view.refresh()
            XCTAssertNotNil(view.secretTimer, "Scenario \(index)")
        }
    }

    func testNativeAvailabilityStillControlsTimerAndOwnerReleases() {
        weak var owner: ChatInputActionsView?
        weak var button: ImageButton?
        autoreleasepool {
            let view = ChatInputActionsView(frame: .zero)
            view.chatInteraction.presentation.hasSetDestructiveTimer = false
            view.refresh()
            XCTAssertNil(view.secretTimer)
            view.chatInteraction.presentation.hasSetDestructiveTimer = true
            view.chatInteraction.presentation.interfaceState.messageEffect = 2
            view.refresh()
            XCTAssertNil(view.secretTimer)
            view.chatInteraction.presentation.interfaceState.messageEffect = nil
            view.refresh()
            XCTAssertNotNil(view.secretTimer)
            owner = view
            button = view.secretTimer
        }
        ComposerAutoDeleteButtonPreferences.shared.setHidden(true)
        XCTAssertNil(owner)
        XCTAssertNil(button)
    }
}

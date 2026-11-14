import AppKit
import SwiftSignalKit
import XCTest

public struct ChatTextInputState {
    var inputText = ""
    var selectionRange = 0..<0
    func isFirstAnimatedEmoji(_ query: String) -> Bool { false }
}
extension String {
    var isSingleEmoji: Bool { false }
    var containsOnlyEmoji: Bool { false }
    var basicEmoji: (String, String?) { (self, nil) }
}
extension NSRange {
    init(string: String, range: Range<String.Index>) { self = NSRange(range, in: string) }
}
public enum ChatPresentationInputQuery: Equatable {
    case none, hashtag(String), mention(query: String, includeRecent: Bool), command(String)
    case contextRequest(addressName: String, query: String), stickers(String), emoji(String, firstWord: Bool)
}
public struct ChatPresentationInterfaceState {
    enum MenuButton: Equatable { case commands, webView(String, String) }
    enum State { case normal, editing }
    struct BotMenu: Equatable {
        var commands: [String]
        var revealed: Bool
        var menuButton: MenuButton
        var isEmpty: Bool {
            switch menuButton {
            case .webView: return false
            case .commands: return commands.isEmpty
            }
        }
    }

    var botMenu: BotMenu?
    var state = State.normal
    var effectiveInput = ChatTextInputState()
    var sendAsPeers: [Int]?
    var currentSendAsPeerId: Int?

    func updateBotMenu(_ update: (BotMenu?) -> BotMenu?) -> Self {
        var value = self
        value.botMenu = update(botMenu)
        return value
    }
}
final class InteractionContext {
    let peerId = 1
}
final class ChatInteraction {
    var presentation = ChatPresentationInterfaceState()
    let interactionContext = InteractionContext()
    var previousAnimation: Bool?
    var updateCount = 0
    var onUpdate: ((ChatPresentationInterfaceState) -> Void)?
    func update(animated: Bool = true, _ update: (ChatPresentationInterfaceState) -> ChatPresentationInterfaceState) {
        updateCount += 1
        previousAnimation = animated
        presentation = update(presentation)
        onUpdate?(presentation)
    }
}
final class Layer {
    func animateAlpha(from: CGFloat, to: CGFloat, duration: Double, timingFunction: TimingFunction? = nil) {}
    func animateScaleCenter(from: CGFloat, to: CGFloat, duration: Double, timingFunction: TimingFunction) {}
}
enum TimingFunction { case easeOut }
class View {
    var frame = NSRect.zero
    var layer: Layer? = Layer()
    var removalCount = 0
    var addCount = 0
    func addSubview(_ view: View) { addCount += 1 }
    init(frame: NSRect = .zero) { self.frame = frame }
}
func performSubviewRemoval(_ view: View, animated: Bool, scale: Bool) { view.removalCount += 1 }
final class ChatInputMenuView: View {
    weak var chatInteraction: ChatInteraction?
    var glassFrame = NSRect(x: 0, y: 0, width: 40, height: 38)
    func setInnerGlassHidden(_ hidden: Bool) {}
    func setSharedGlassGhost(_ ghost: Int?) {}
}
final class ChatInputSendAsView: View {
    func update(_ peers: [Int], currentPeerId: Int, chatInteraction: ChatInteraction, animated: Bool, photoSize: CGFloat) {}
}
enum Transition { case immediate, animated(duration: Double, curve: TimingFunction) }
final class TextView {
    let min_height: CGFloat = 36
    let max_height: CGFloat = 160
    func height(for width: CGFloat) -> CGFloat { width > 120 ? 36 : 72 }
}
struct DictationHeight {
    func fit(_ height: CGFloat, transcribing: Bool) -> CGFloat { height }
}
struct ActionsView { let visibleWidth: CGFloat = 40 }

final class ComposerFixture {
    let chatInteraction = ChatInteraction()
    let composerBotCommandsDisposable = MetaDisposable()
    let contentView = View()
    let textFieldContainer = View()
    var botMenuView: ChatInputMenuView?
    var sendAsView: ChatInputSendAsView?
    var sendAsHiddenByState = false
    let frame = NSRect(x: 0, y: 0, width: 650, height: 80)
    let window: Int? = 1
    let botMenuGhost: Int? = 1
    var layouts = 0
    var heightUpdates = 0
    let attachView = View(frame: .init(x: 0, y: 0, width: 40, height: 40))
    let actionsView = ActionsView()
    let textView = TextView()
    let dictationHeight = DictationHeight()
    let isTranscribing = false
    let aiRewriteHeightFloor: CGFloat = 0

    func bind() {
        chatInteraction.onUpdate = { [weak self] state in self?.updateAttachments(state, false) }
__BIND__
    }
__UPDATE__
__ATTACHMENTS__
__WIDTH__
    func sendSlot(gap: CGFloat) -> (outside: CGFloat, inField: CGFloat) { (gap + 40, 0) }
    func updateLayout(size: NSSize, transition: Transition) { layouts += 1 }
    func inputDidUpdateLayout(animated: Bool) { heightUpdates += 1 }

    deinit { composerBotCommandsDisposable.dispose() }
}

final class ComposerBotCommandsTests: XCTestCase {
    override func setUp() { ComposerBotCommandsPreferences.shared.setHidden(false) }
    override func tearDown() { ComposerBotCommandsPreferences.shared.setHidden(false) }

    func testDefaultVisibleAndSignalPersistsAndDeduplicates() throws {
        let suite = "Gergram.BotCommandsTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ComposerBotCommandsPreferences(defaults: defaults)
        var values: [Bool] = []
        let observation = preferences.signal.start(next: { values.append($0) })
        defer { observation.dispose() }
        XCTAssertFalse(preferences.hidesButton)
        preferences.setHidden(true)
        preferences.setHidden(true)
        XCTAssertTrue(ComposerBotCommandsPreferences(defaults: defaults).hidesButton)
        preferences.setHidden(false)
        XCTAssertEqual(values, [false, true, false])
    }

    func testToggleUsesNativeRemovalAndReleasesTextWidthAtTwoSizes() throws {
        let fixture = ComposerFixture()
        fixture.chatInteraction.presentation.botMenu = .init(commands: ["help"], revealed: false, menuButton: .commands)
        fixture.bind()
        let oldView = try XCTUnwrap(fixture.botMenuView)
        let narrow = fixture.textViewSize(224).0
        let wide = fixture.textViewSize(650).0
        ComposerBotCommandsPreferences.shared.setHidden(true)
        XCTAssertNil(fixture.botMenuView)
        XCTAssertEqual(oldView.removalCount, 1)
        XCTAssertEqual(fixture.textViewSize(224).0.width - narrow.width, 50)
        XCTAssertEqual(fixture.textViewSize(650).0.width - wide.width, 50)
        ComposerBotCommandsPreferences.shared.setHidden(false)
        XCTAssertNotNil(fixture.botMenuView)
        XCTAssertEqual(fixture.textViewSize(224).0, narrow)
        XCTAssertEqual(fixture.textViewSize(650).0, wide)
        XCTAssertEqual(fixture.heightUpdates, 3)
    }

    func testHidingRevealedCommandsPreservesDraftAndRoutesSlashCommandNormally() throws {
        let fixture = ComposerFixture()
        fixture.chatInteraction.presentation.botMenu = .init(commands: ["help"], revealed: true, menuButton: .commands)
        fixture.chatInteraction.presentation.effectiveInput = .init(inputText: "/he", selectionRange: 3..<3)
        fixture.bind()
        XCTAssertEqual(inputContextQueryForChatPresentationIntefaceState(fixture.chatInteraction.presentation, includeContext: true), .command(""))
        ComposerBotCommandsPreferences.shared.setHidden(true)
        XCTAssertFalse(try XCTUnwrap(fixture.chatInteraction.presentation.botMenu).revealed)
        XCTAssertEqual(fixture.chatInteraction.presentation.effectiveInput.inputText, "/he")
        XCTAssertEqual(fixture.chatInteraction.presentation.effectiveInput.selectionRange, 3..<3)
        XCTAssertEqual(inputContextQueryForChatPresentationIntefaceState(fixture.chatInteraction.presentation, includeContext: true), .command("he"))
        XCTAssertEqual(fixture.chatInteraction.updateCount, 1)
        XCTAssertEqual(fixture.chatInteraction.previousAnimation, false)
        ComposerBotCommandsPreferences.shared.setHidden(false)
        XCTAssertNotNil(fixture.botMenuView)
        XCTAssertFalse(try XCTUnwrap(fixture.chatInteraction.presentation.botMenu).revealed)
    }

    func testWebAppMenuStillVisibleAndEmptyCommandsStillUnavailable() throws {
        let fixture = ComposerFixture()
        let webApp = ChatPresentationInterfaceState.BotMenu(commands: [], revealed: false, menuButton: .webView("Open", "https://example.com"))
        fixture.chatInteraction.presentation.botMenu = webApp
        fixture.bind()
        let webAppView = try XCTUnwrap(fixture.botMenuView)
        ComposerBotCommandsPreferences.shared.setHidden(true)
        XCTAssertTrue(fixture.botMenuView === webAppView)
        XCTAssertEqual(fixture.chatInteraction.presentation.botMenu, webApp)
        XCTAssertEqual(fixture.chatInteraction.updateCount, 0)
        fixture.chatInteraction.update {
            $0.updateBotMenu { _ in .init(commands: [], revealed: false, menuButton: .commands) }
        }
        XCTAssertNil(fixture.botMenuView)
        ComposerBotCommandsPreferences.shared.setHidden(false)
        XCTAssertNil(fixture.botMenuView)
    }

    func testHiddenPreferenceAppliesToNewViewsWithoutRetainingTheOldComposer() {
        ComposerBotCommandsPreferences.shared.setHidden(true)
        var fixture: ComposerFixture? = ComposerFixture()
        weak var oldFixture = fixture
        fixture?.chatInteraction.presentation.botMenu = .init(commands: ["help"], revealed: false, menuButton: .commands)
        fixture?.bind()
        XCTAssertNil(fixture?.botMenuView)
        fixture = nil
        XCTAssertNil(oldFixture)
        ComposerBotCommandsPreferences.shared.setHidden(false)
    }
}

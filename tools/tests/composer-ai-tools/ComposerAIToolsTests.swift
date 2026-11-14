import AppKit
import Foundation
import SwiftSignalKit
import XCTest

private enum ChatState { case normal, editing, recording }
private enum EditStateLoading { case none, progressing }
private struct EditState { var loadingState: EditStateLoading }
private struct InterfaceState { var editState: EditState? }
private struct Peer { var isSecretChat = false }
private struct SlowMode { var hasLocked = false }
private struct Presentation {
    var state = ChatState.normal
    var interfaceState = InterfaceState()
    var peer: Peer? = .init()
    var slowMode: SlowMode?
}
private struct AppConfiguration { var isRichTextEditorEnabled = true }
private final class InteractionContext { var appConfiguration = AppConfiguration() }
private final class ChatInteraction {
    var presentation = Presentation()
    let interactionContext = InteractionContext()
    private(set) var editorOpened = 0
    func openAIEditor(morphSource: (() -> NSView?)?) {
        precondition(morphSource?() != nil)
        editorOpened += 1
    }
}
private final class Button: NSView {
    var isEnabled = true
    var userInteractionEnabled = true
}
private struct Strings { let translateAIEditor = "AI Editor" }
private func strings() -> Strings { Strings() }
private struct MenuAnimation {
    static let menu_translate = MenuAnimation()
    var value: Int { 0 }
}
private struct ContextMenuItem {
    let title: String
    let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void, itemImage: Int) {
        self.title = title
        self.handler = handler
    }
}
private final class AttachView: NSView {
    let button = Button(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
    let chatInteraction: ChatInteraction
    var canOpenAIEditorFromMenu: (() -> Bool)?

    init(chatInteraction: ChatInteraction) {
        self.chatInteraction = chatInteraction
        super.init(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        addSubview(button)
    }

    required init?(coder: NSCoder) { fatalError() }

    func menuItems() -> [ContextMenuItem] {
        var items = [ContextMenuItem("File", handler: {}, itemImage: 0)]
        __MENU_ITEM__
        return items
    }
}
private final class TextView {
    var lines = 4
    func numberOfLines(for width: CGFloat) -> Int { lines }
}
private final class Container: NSView {
    let chatInteraction = ChatInteraction()
    lazy var attachView = AttachView(chatInteraction: chatInteraction)
    let textView = TextView()
    var richDraftPreview: NSView?
    private(set) var layoutInvalidations = 0

    override var needsLayout: Bool {
        didSet {
            if needsLayout {
                layoutInvalidations += 1
            }
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(attachView)
        __MENU_BINDING__
    }

    required init?(coder: NSCoder) { fatalError() }

    func textViewSize(_ width: CGFloat) -> (NSSize, CGFloat) { (NSSize(width: width, height: 50), 50) }

    __ELIGIBILITY__

    func visibility() -> (ai: Bool, richExpand: Bool) {
        let textSize = textViewSize(bounds.width).0
        __AI_LAYOUT__
        __RICH_LAYOUT__
        return (showAi, showExpand)
    }
}
private final class InputViewOwner {
    let container = Container(frame: NSRect(x: 0, y: 0, width: 150, height: 50))
    let composerAIToolsDisposable = MetaDisposable()

    init() {
        __PREFERENCE_BINDING__
    }

    deinit { composerAIToolsDisposable.dispose() }
}

final class ComposerAIToolsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ComposerAIToolsButtonPreferences.shared.setHidden(false)
    }

    override func tearDown() {
        ComposerAIToolsButtonPreferences.shared.setHidden(false)
        super.tearDown()
    }

    func testPreferenceDefaultsPersistsAndPublishesDistinctValues() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preference = ComposerAIToolsButtonPreferences(defaults: defaults)
        var values = [Bool]()
        let listener = preference.signal.start(next: { values.append($0) })
        defer { listener.dispose() }
        XCTAssertFalse(preference.hidesButton)
        preference.setHidden(true)
        preference.setHidden(true)
        XCTAssertTrue(ComposerAIToolsButtonPreferences(defaults: defaults).hidesButton)
        preference.setHidden(false)
        XCTAssertEqual(values, [false, true, false])
    }

    func testHidesOnlyNativeButtonAndLeavesExplicitMenuAndRichExpand() {
        let container = Container(frame: NSRect(x: 0, y: 0, width: 150, height: 50))
        XCTAssertTrue(container.visibility().ai)
        XCTAssertTrue(container.visibility().richExpand)
        XCTAssertEqual(container.attachView.menuItems().map(\.title), ["File"])
        ComposerAIToolsButtonPreferences.shared.setHidden(true)
        XCTAssertFalse(container.visibility().ai)
        XCTAssertTrue(container.visibility().richExpand)
        let menu = container.attachView.menuItems()
        XCTAssertEqual(menu.map(\.title), ["File", "AI Editor"])
        menu.last?.handler()
        XCTAssertEqual(container.chatInteraction.editorOpened, 1)
        ComposerAIToolsButtonPreferences.shared.setHidden(false)
        XCTAssertTrue(container.visibility().ai)
        XCTAssertEqual(container.attachView.menuItems().map(\.title), ["File"])
        menu.last?.handler()
        XCTAssertEqual(container.chatInteraction.editorOpened, 1)
    }

    func testUnavailablePaperclipKeepsAnOtherwiseEligibleButton() {
        let container = Container(frame: .zero)
        ComposerAIToolsButtonPreferences.shared.setHidden(true)
        container.attachView.isHidden = true
        XCTAssertTrue(container.visibility().ai)
        XCTAssertEqual(container.attachView.menuItems().map(\.title), ["File"])
        container.attachView.isHidden = false
        container.attachView.button.isEnabled = false
        XCTAssertTrue(container.visibility().ai)
        container.attachView.button.isEnabled = true
        container.attachView.button.userInteractionEnabled = false
        XCTAssertTrue(container.visibility().ai)
        container.attachView.button.userInteractionEnabled = true
        container.chatInteraction.presentation.slowMode = .init(hasLocked: true)
        XCTAssertTrue(container.visibility().ai)
        container.chatInteraction.presentation.slowMode = .init()
        container.chatInteraction.presentation.peer = nil
        XCTAssertTrue(container.visibility().ai)
    }

    func testFallbackRevalidatesNativeStateAndKeepsExistingRichDraft() {
        let container = Container(frame: .zero)
        let interaction = container.chatInteraction
        ComposerAIToolsButtonPreferences.shared.setHidden(true)
        let oldMenu = container.attachView.menuItems()
        container.textView.lines = 3
        XCTAssertFalse(container.visibility().ai)
        XCTAssertFalse(container.visibility().richExpand)
        XCTAssertEqual(container.attachView.menuItems().map(\.title), ["File"])
        oldMenu.last?.handler()
        XCTAssertEqual(interaction.editorOpened, 0)
        container.richDraftPreview = NSView()
        XCTAssertTrue(container.visibility().richExpand)
        container.textView.lines = 4
        interaction.presentation.state = .editing
        XCTAssertEqual(container.attachView.menuItems().map(\.title), ["File", "AI Editor"])
        interaction.presentation.interfaceState.editState = .init(loadingState: .progressing)
        XCTAssertEqual(container.attachView.menuItems().map(\.title), ["File"])
        interaction.presentation.interfaceState.editState = nil
        interaction.presentation.peer?.isSecretChat = true
        XCTAssertEqual(container.attachView.menuItems().map(\.title), ["File"])
        interaction.presentation.peer?.isSecretChat = false
        interaction.presentation.state = .recording
        XCTAssertEqual(container.attachView.menuItems().map(\.title), ["File"])
    }

    func testLivePreferenceInvalidatesLayoutAndReleasesOwner() {
        var owner: InputViewOwner? = InputViewOwner()
        let container = owner!.container
        let initial = container.layoutInvalidations
        ComposerAIToolsButtonPreferences.shared.setHidden(true)
        XCTAssertEqual(container.layoutInvalidations, initial + 1)
        weak let released = owner
        owner = nil
        XCTAssertNil(released)
        ComposerAIToolsButtonPreferences.shared.setHidden(false)
        XCTAssertEqual(container.layoutInvalidations, initial + 1)
    }
}

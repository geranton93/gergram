import AppKit
import SwiftSignalKit
// Use native menu objects and stub the account data, window and navigation.
typealias AccountRecordId = Int
final class MenuSlot { var menu: NSMenu? }
final class TestWindow {
    var attachedSheet: NSWindow?
    let isKeyWindow = false
    func deminiaturize(_ sender: Any?) {}
    func makeKeyAndOrderFront(_ sender: Any?) {}
}
let mainWindow = TestWindow()
func hasModals(_ window: TestWindow) -> Bool { false }
struct Labels {
    let statusBarActivate = "Activate"
    let statusBarHide = "Hide"
    let statusBarQuit = "Quit"
    let accountSettingsMyProfile = "My Profile"
    let peerSavedMessages = "Saved Messages"
}
func strings() -> Labels { Labels() }
var appDelegate: TestDelegate?
final class ContextMenuItem: NSMenuItem {
    private var handler: (() -> Void)?
    convenience init(_ title: String, handler: @escaping () -> Void, image: NSImage? = nil, dynamicTitle: (() -> String)? = nil, state: NSControl.StateValue? = nil) {
        self.init(title: dynamicTitle?() ?? title, action: nil, keyEquivalent: "")
        self.image = image
        self.handler = handler
        if let state { self.state = state }
    }
}
func ContextSeparatorItem() -> NSMenuItem { .separator() }
struct Account { let id: Int; let peerId: Int }
struct Peer { let displayTitle: String }
struct AccountWithInfo { let account: Account; let peer: Peer }
final class SharedMenuFixture {
    let statusItem: MenuSlot? = MenuSlot()
    weak var streamerModeStatusItem: NSMenuItem?
    let statusMenuVisibilityDisposable = MetaDisposable()
    var visibleStatusMenuActions = StreamerModeMenuBarPreferences.defaultActions
    var callStatusBarMenuItems: (() -> [ContextMenuItem])? { didSet { updateStatusBarMenuItem() } }
    var isLocked = false { didSet { updateStatusBarMenuItem() } }
    var activeAccountsInfoValue: (primary: AccountRecordId?, accounts: [AccountWithInfo])?
    var activeAccountsValue: (primary: Account?, accounts: [Account])?
    var accountPhotos: [Int: CGImage] = [:]
    func switchToAccount(id: Int, action: (() -> Void)?) {}
    func rebuild() { updateStatusBarMenuItem() }
    init(preferences: StreamerModeMenuBarPreferences) {
        updateStatusBarMenuItem()
__OBSERVE__
    }
    deinit { statusMenuVisibilityDisposable.dispose() }
__GATE__
__MENU__

}
enum ChatLocation: Equatable { case peer(Int) }
enum ChatMode { case history }
final class ChatController {
    let chatLocation: ChatLocation
    let mode = ChatMode.history
    let accountId: Int
    init(context: TestContext, chatLocation: ChatLocation) { self.chatLocation = chatLocation; accountId = context.account.id }
}
final class ProfileView { var shakes = 0; func shake(beep: Bool) { shakes += 1 } }
final class PeerInfoController {
    let peerId: Int
    let view = ProfileView()
    init(context: TestContext, peer: TelegramUser) { peerId = peer.id }
}
struct TelegramUser { let id: Int; func restrictionText(_ settings: Bool) -> String? { nil } }
final class Navigation {
    var controller: Any?
    var pushes = 0
    func push(_ item: Any, _ animated: Bool = true) { controller = item; pushes += 1 }
}
final class TestContext {
    let account: Account
    let window = TestWindow()
    var isCurrent = true
    var isExternal = false
    var isFrozen = false
    var frozenAlerts = 0
    let contentSettings = true
    let navigation = Navigation()
    var myPeer: Any?
    var peerId: Int { account.peerId }
    var bindings: TestContext { self }
    func rootNavigation() -> Navigation { navigation }
    func freezeAlert() { frozenAlerts += 1 }
    init(_ account: Account) { self.account = account; myPeer = TelegramUser(id: account.peerId) }
}
struct ContextHolder { let context: TestContext }
final class NotificationManager { var isLocked = false }
struct AppContext { let sharedContext: SharedMenuFixture; let notificationManager: NotificationManager }
final class TestDelegate: NSObject {
    var authContextValue: NSObject?
    var sharedApplicationContextValue: AppContext?
    var contextValue: ContextHolder?
    func makeStreamerModeMenuItem() -> NSMenuItem { NSMenuItem(title: "Streamer Mode", action: nil, keyEquivalent: "") }
__ACTIONS__

}

let suite = "Gergram.StatusActions.\(UUID())"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let legacy = "gergram.menuBar.showsStreamerMode"
defaults.set(false, forKey: legacy)
let preferences = StreamerModeMenuBarPreferences(defaults: defaults)
var owner: SharedMenuFixture? = SharedMenuFixture(preferences: preferences)
appDelegate = TestDelegate()
let notifications = NotificationManager()
appDelegate?.sharedApplicationContextValue = AppContext(sharedContext: owner!, notificationManager: notifications)
let a = TestContext(Account(id: 1, peerId: 11))
let b = TestContext(Account(id: 2, peerId: 21))
appDelegate?.contextValue = ContextHolder(context: a)
owner?.activeAccountsValue = (a.account, [a.account, b.account])
owner?.rebuild()
func item(_ title: String) -> NSMenuItem? { owner?.statusItem?.menu?.items.first(where: { $0.title == title }) }
func invoke(_ item: NSMenuItem) {
    let selector = item.action!
    let target = item.target as? TestDelegate
    precondition(target?.responds(to: selector) == true)
    _ = target?.perform(selector, with: item)
}
precondition(item("Streamer Mode") == nil && item("My Profile") == nil && item("Saved Messages") == nil)
preferences.setVisible(true, for: .myProfile)
let originalProfile = item("My Profile")!
invoke(originalProfile)
precondition((a.navigation.controller as? PeerInfoController)?.peerId == 11 && a.navigation.pushes == 1)
invoke(originalProfile)
precondition(a.navigation.pushes == 1 && (a.navigation.controller as? PeerInfoController)?.view.shakes == 1)
preferences.setVisible(true, for: .savedMessages)
invoke(originalProfile)
precondition((a.navigation.controller as? PeerInfoController)?.view.shakes == 1)
let staleSaved = item("Saved Messages")!
owner?.activeAccountsValue = (b.account, [a.account, b.account])
invoke(staleSaved)
precondition(a.navigation.pushes == 1)
appDelegate?.contextValue = ContextHolder(context: b)
invoke(staleSaved)
precondition(b.navigation.pushes == 0)
owner?.rebuild()
let saved = item("Saved Messages")!
notifications.isLocked = true
invoke(saved)
notifications.isLocked = false
appDelegate?.authContextValue = NSObject()
invoke(saved)
appDelegate?.authContextValue = nil
precondition(b.navigation.pushes == 0)
invoke(saved)
invoke(saved)
precondition((b.navigation.controller as? ChatController)?.accountId == 2 && (b.navigation.controller as? ChatController)?.chatLocation == .peer(21) && b.navigation.pushes == 1)
b.isFrozen = true
invoke(item("My Profile")!)
precondition(b.navigation.pushes == 1 && b.frozenAlerts == 1)
b.isFrozen = false
invoke(item("My Profile")!)
precondition(b.navigation.pushes == 2 && (b.navigation.controller as? PeerInfoController)?.peerId == 21)
owner?.callStatusBarMenuItems = { [ContextMenuItem("Call", handler: {})] }
let callMenu = owner?.statusItem?.menu
preferences.setVisible(true)
precondition(owner?.statusItem?.menu === callMenu && item("Call") != nil)
invoke(saved)
precondition(b.navigation.pushes == 2)
owner?.callStatusBarMenuItems = nil
owner?.isLocked = true
precondition(item("My Profile") == nil && item("Saved Messages") == nil && item("Streamer Mode") != nil)
owner?.isLocked = false
preferences.reset()
precondition(item("My Profile") == nil && item("Saved Messages") == nil && item("Streamer Mode") != nil)
owner?.activeAccountsInfoValue = (b.account.id, [AccountWithInfo(account: a.account, peer: Peer(displayTitle: "A")), AccountWithInfo(account: b.account, peer: Peer(displayTitle: "B"))])
owner?.rebuild()
let accountMenu = owner?.statusItem?.menu
weak var weakOwner = owner
appDelegate?.sharedApplicationContextValue = nil
owner = nil
precondition(weakOwner == nil)
withExtendedLifetime(accountMenu) {}
print("PASS status menu defaults, active account and menu identity, lock/auth/call, synchronous routes, owner release")

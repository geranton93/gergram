import Foundation

public typealias PeerId = Int
public typealias ContentSettings = Bool

final class TelegramChannel {
    enum Participation { case member, left, kicked }
    let id: PeerId
    let isSupergroup: Bool
    var isChannel: Bool { !isSupergroup }
    var isMonoForum = false
    var participationStatus = Participation.member
    var restricted = false

    init(_ id: PeerId, group: Bool) {
        self.id = id
        self.isSupergroup = group
    }

    func restrictionText(_ contentSettings: ContentSettings?) -> String? {
        restricted && contentSettings != true ? "Restricted" : nil
    }
}

struct CachedChannelData {
    enum LinkedDiscussion {
        case unknown, known(PeerId?)

        var peerId: PeerId? {
            if case let .known(id) = self { return id }
            return nil
        }
    }

    var isNotAccessible = false
    var linkedDiscussionPeerId: LinkedDiscussion
}

public struct PeerView {
    var peerId: PeerId
    var peers: [PeerId: Any]
    var cachedData: Any?
}

__POLICY__

final class Window {}
final class View {
    var window: Window?
}
final class Navigation {
    weak var controller: AnyObject?
}
final class Context {
    var isCurrent = true
    var isExternal = false
    var isFrozen = false
    let window = Window()
    var contentSettings: ContentSettings? = false
}
struct MenuAnimation {
    static let menu_channel = MenuAnimation()
    static let menu_plus = MenuAnimation()
    var value: Self { self }
}
struct Strings {
    let storyAvatarContextOpenChannel = "Open Channel"
    let peerInfoActionMore = "More"
}
func strings() -> Strings { Strings() }
struct ContextMenuItem {
    let title: String
    let handler: () -> Void
    init(_ title: String, handler: @escaping () -> Void, itemImage: MenuAnimation) {
        self.title = title
        self.handler = handler
    }
}
struct SubActionItem {
    let text: String
    let animation: MenuAnimation
    let destruct: Bool
    let action: () -> Void

    init(text: String, animation: MenuAnimation, destruct: Bool = false, action: @escaping () -> Void) {
        self.text = text
        self.animation = animation
        self.destruct = destruct
        self.action = action
    }
}
final class ActionItem {
    let text: String
    let animation: MenuAnimation
    let destruct: Bool
    let action: () -> Void
    let subItems: [SubActionItem]?

    init(text: String, color: Int = 0, image: Int = 0, animation: MenuAnimation = .menu_plus, destruct: Bool = false, action: @escaping () -> Void = {}, subItems: [SubActionItem]? = nil) {
        self.text = text
        self.animation = animation
        self.destruct = destruct
        self.action = action
        self.subItems = subItems
    }
}
enum AnalyticsScreen { case peerInfoTopic, peerInfo }
enum AnalyticsEvents {
    static func menuSelect(peerInfoMore: Int, screen: AnalyticsScreen) -> Int { 0 }
}
struct Analytics {
    static let shared = Analytics()
    func send(_ event: Int) {}
}
struct Theme {
    struct Icons { let profile_more = 0 }
    let icons = Icons()
}
final class ChatInteraction {
    private(set) var opened: [PeerId] = []
    func openInfo(_ peerId: PeerId, _ toChat: Bool, _ postId: Int?, _ action: Int?) {
        precondition(toChat && postId == nil && action == nil)
        opened.append(peerId)
    }
}
enum Mode { case history, thread }
final class ChatController {
    let context = Context()
    let genericView = View()
    let navigationController: Navigation? = Navigation()
    var mode = Mode.history
    var isAdChat = false
    var chatLocation: PeerId = 1
    var currentPeerView: PeerView?
    let chatInteraction = ChatInteraction()

    init() {
        genericView.window = context.window
        navigationController?.controller = self
    }

    func makeMenu() -> [ContextMenuItem] {
        guard let peerView = currentPeerView else { return [] }
        let peerId = chatLocation
        let chatLocation = self.chatLocation
        var items: [ContextMenuItem] = []
        __CHAT__
        return items
    }
}
final class GroupInfoArguments {
    var isAd = false
    var openDiscussionLinkedChannel: ((PeerId) -> Void)?
    private(set) var opened: [PeerId] = []
    func peerChat(_ id: PeerId) { opened.append(id) }
}
struct CurrentPeerView {
    var view: PeerView?
    func with<Result>(_ read: (PeerView?) -> Result) -> Result { read(view) }
}
final class ProfileController {
    enum State { case Normal, Edit }
    let context = Context()
    let view = View()
    let navigationController: Navigation? = Navigation()
    let _groupArguments = GroupInfoArguments()
    var peerId: PeerId = 1
    var threadInfo: Int?
    var state = State.Normal
    var peerView = CurrentPeerView()

    init() {
        view.window = context.window
        navigationController?.controller = self
        __PROFILE_ACTION__
    }
}
struct ProfileItem {
    var threadId: Int?
    var editing = false
    let accentColor = 0
    let peerView: PeerView
    let context: Context
}
func profileActions(item: ProfileItem, arguments: GroupInfoArguments, baseItems: [ActionItem] = [], rowItemsCount: Int = 3) -> [ActionItem] {
    let analyticsItems: [ObjectIdentifier: Int] = [:]
    let theme = Theme()
    var items = baseItems
    var moreItems: [SubActionItem] = []
    __PROFILE__
    __PROFILE_MORE__
    return items
}

let group = TelegramChannel(1, group: true)
let channel = TelegramChannel(2, group: false)
let replacement = TelegramChannel(3, group: false)
let cache = CachedChannelData(linkedDiscussionPeerId: .known(channel.id))
let valid = PeerView(peerId: group.id, peers: [1: group, 2: channel, 3: replacement], cachedData: cache)
precondition(discussionLinkedChannelId(in: valid, contentSettings: false) == 2)
channel.participationStatus = .left
precondition(discussionLinkedChannelId(in: valid, contentSettings: false) == 2)
channel.participationStatus = .kicked
precondition(discussionLinkedChannelId(in: valid, contentSettings: false) == nil)
channel.participationStatus = .member
channel.restricted = true
precondition(discussionLinkedChannelId(in: valid, contentSettings: false) == nil)
precondition(discussionLinkedChannelId(in: valid, contentSettings: true) == 2)
channel.restricted = false
group.restricted = true
precondition(discussionLinkedChannelId(in: valid, contentSettings: false) == nil)
group.restricted = false
group.isMonoForum = true
precondition(discussionLinkedChannelId(in: valid, contentSettings: false) == nil)
group.isMonoForum = false

for data: Any? in [
    nil,
    CachedChannelData(linkedDiscussionPeerId: .unknown),
    CachedChannelData(linkedDiscussionPeerId: .known(nil)),
    CachedChannelData(linkedDiscussionPeerId: .known(1)),
    CachedChannelData(linkedDiscussionPeerId: .known(4)),
    CachedChannelData(isNotAccessible: true, linkedDiscussionPeerId: .known(2)),
] {
    var changed = valid
    changed.cachedData = data
    precondition(discussionLinkedChannelId(in: changed, contentSettings: false) == nil)
}
var changedTarget = valid
changedTarget.peers[2] = TelegramChannel(2, group: true)
precondition(discussionLinkedChannelId(in: changedTarget, contentSettings: false) == nil)
var changedSource = valid
changedSource.peers[1] = TelegramChannel(1, group: false)
precondition(discussionLinkedChannelId(in: changedSource, contentSettings: false) == nil)

var relinked = valid
relinked.cachedData = CachedChannelData(linkedDiscussionPeerId: .known(3))
let chat = ChatController()
chat.currentPeerView = valid
let menu = chat.makeMenu()
precondition(menu.count == 1 && menu[0].title == "Open Channel")
menu[0].handler()
precondition(chat.chatInteraction.opened == [2])
chat.currentPeerView = relinked
menu[0].handler()
precondition(chat.chatInteraction.opened == [2])
let updatedMenu = chat.makeMenu()
updatedMenu[0].handler()
precondition(chat.chatInteraction.opened == [2, 3])
chat.mode = .thread
updatedMenu[0].handler()
chat.mode = .history
chat.isAdChat = true
precondition(chat.makeMenu().isEmpty)
updatedMenu[0].handler()
chat.isAdChat = false
chat.context.isCurrent = false
updatedMenu[0].handler()
chat.context.isCurrent = true
chat.navigationController?.controller = nil
updatedMenu[0].handler()
precondition(chat.chatInteraction.opened == [2, 3])

let profile = ProfileController()
profile.peerView.view = valid
let item = ProfileItem(peerView: valid, context: profile.context)
let actions = profileActions(item: item, arguments: profile._groupArguments)
precondition(actions.count == 1 && actions[0].text == "More")
let openChannel = actions[0].subItems![0]
precondition(openChannel.text == "Open Channel")
openChannel.action()
precondition(profile._groupArguments.opened == [2])
profile.peerView.view = relinked
openChannel.action()
profile.peerView.view = valid
profile.context.isFrozen = true
openChannel.action()
profile.context.isFrozen = false
profile.state = .Edit
openChannel.action()
profile.state = .Normal
profile.threadInfo = 44
openChannel.action()
profile.threadInfo = nil
profile.view.window = nil
openChannel.action()
profile.view.window = profile.context.window
profile._groupArguments.isAd = true
openChannel.action()
precondition(profileActions(item: item, arguments: profile._groupArguments).isEmpty)
profile._groupArguments.isAd = false
precondition(profile._groupArguments.opened == [2])

let native = [ActionItem(text: "Mute"), ActionItem(text: "Voice Chat"), ActionItem(text: "Leave", destruct: true)]
for width in 1...4 {
    let menu = profileActions(item: item, arguments: profile._groupArguments, baseItems: native, rowItemsCount: width)
    precondition(menu.count <= width && menu.last?.text == "More")
    let more = menu.last!.subItems!
    precondition(more.filter { $0.text == "Open Channel" }.count == 1)
    if let leave = more.firstIndex(where: { $0.destruct }) {
        precondition(more[leave - 1].text == "Open Channel")
    }
}
var editingItem = item
editingItem.editing = true
precondition(profileActions(item: editingItem, arguments: profile._groupArguments, baseItems: native).last === native.last)
var topicItem = item
topicItem.threadId = 10
precondition(profileActions(item: topicItem, arguments: profile._groupArguments).isEmpty)

print("Discussion linked-channel eligibility and navigation ownership passed")

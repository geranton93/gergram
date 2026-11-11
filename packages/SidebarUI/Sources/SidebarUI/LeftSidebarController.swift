import Cocoa
import TelegramContext
import TelegramTheme
import TelegramUtils
import Localization
import GeneralRows
import InputDataUI

import TGUIKit
import Postbox
import SwiftSignalKit
import TelegramCore
import InAppSettings

private func readAllInFilter(_ filter: ChatListFilter?, context: any AccountContextProtocol, environment: SidebarUIEnvironment) {
    let _ = (environment.filterPredicates
    |> take(1)
    |> mapToSignal { predicateForFilter -> Signal<Never, NoError> in
        guard let filterPredicate = predicateForFilter(filter) else {
            return .complete()
        }
        var items: [(groupId: EngineChatList.Group, filterPredicate: ChatListFilterPredicate?)] = [(.root, filterPredicate)]
        for groupId in filterPredicate.includeAdditionalPeerGroupIds {
            items.append((EngineChatList.Group(groupId), filterPredicate))
        }
        return context.engine.messages.markAllChatsAsReadInteractively(items: items)
    }).start()
}

public func filterContextMenuItems(_ filter: ChatListFilter, unreadCount: Int?, includeAllMuted: Bool? = nil, context: any AccountContextProtocol, environment: SidebarUIEnvironment, isHidden: Bool = false) -> [ContextMenuItem] {
    var data = filter.data
    var items = sidebarMenuItems(filter: filter, unreadCount: unreadCount, includeAllMuted: includeAllMuted, image: environment.menuImage, perform: { action in
        switch action {
        case .edit:
            context.bindings.rootNavigation().push(ChatListFilterController(context: context, environment: environment, filter: filter))
        case .editFolders:
            context.bindings.rootNavigation().push(ChatListFiltersListController(context: context, environment: environment))
        case .addChats:
            guard let current = data else { return }
            environment.selectPeers(defaultSelectedIds: Set(current.includePeers.peers), categories: [], limit: 100, limitReachedText: strings().chatListFilterIncludeLimitReached, callback: { peerIds in
                return context.engine.peers.updateChatListFiltersInteractively({ filters in
                    var filters = filters
                    guard var updated = data else { return filters }
                    updated = sidebarMenuAddingPeers(updated, peerIds: peerIds)
                    data = updated
                    let filter = filter.withUpdatedData(updated)
                    if let index = filters.firstIndex(where: { $0.sidebarId == filter.sidebarId }) {
                        filters[index] = filter
                    }
                    return filters
                }) |> ignoreValues
            })
        case .markRead:
            readAllInFilter(filter, context: context, environment: environment)
        case let .mute(muted):
            guard let data = data else { return }
            _ = context.engine.peers.updateMultiplePeerMuteSettings(peerIds: data.includePeers.peers, muted: muted).start()
        case .share:
            environment.shareFolder(filter)
        case .delete:
            if filter.data?.isShared == true {
                environment.deleteSharedFolder(filter)
            } else {
                environment.confirmFolderAction(header: strings().chatListFilterConfirmRemoveHeader, information: strings().chatListFilterConfirmRemoveText, ok: strings().chatListFilterConfirmRemoveOK, successHandler: {
                    _ = context.engine.peers.updateChatListFiltersInteractively({ filters in
                        var filters = filters
                        filters.removeAll(where: { $0.sidebarId == filter.sidebarId })
                        return filters
                    }).start()
                })
            }
        }
    })
    if case let .filter(id, _, _, _) = filter {
        let key = isHidden ? "Gergram.Folders.ShowFolder" : "Gergram.Folders.HideFolder"
        items.append(ContextMenuItem(localizedString(key), handler: {
            _ = updateChatListFolderSettings(context.account.postbox) { settings in
                settings.withUpdatedPresentation { presentation in
                    if isHidden {
                        presentation.hiddenFolderIds.remove(id)
                    } else {
                        presentation.hiddenFolderIds.insert(id)
                    }
                }
            }.start()
        }))
    }
    return items
}

private final class LeftSidebarArguments {
    let environment: SidebarUIEnvironment
    let context: any AccountContextProtocol
    let callback:(ChatListFilter)->Void
    let menuItems:(ChatListFilter, Int?, Bool?)->[ContextMenuItem]
    init(context: any AccountContextProtocol, environment: SidebarUIEnvironment, callback: @escaping(ChatListFilter)->Void, menuItems: @escaping(ChatListFilter, Int?, Bool?)->[ContextMenuItem]) {
        self.environment = environment
        self.context = context
        self.callback = callback
        self.menuItems = menuItems
    }
}


public final class LeftSidebarView: LiquidGlassView {
    fileprivate let tableView = TableView()
    fileprivate var environment: SidebarUIEnvironment?
    fileprivate let edit = ImageButton()

    /// 20pt on macOS 26+ to match the liquid-glass look (on macOS 27 the
    /// window radius is raised to 28pt through private API, keeping this
    /// inset sidebar concentric). Older systems keep the subtle 8pt.
    private static var glassCornerRadius: CGFloat {
        if #available(macOS 26.0, *) {
            return 20
        }
        return 8
    }
    public static let inset = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 0)

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect, cornerRadius: LeftSidebarView.glassCornerRadius, hasShadow: false, hasBorder: true, tintAlpha: 0.65)

        backgroundColor = .clear

        addSubview(tableView)
        addSubview(edit)
        tableView.getBackgroundColor = {
            return .clear
        }

        edit.autohighlight = false
        edit.scaleOnClick = true
        edit.setAccessibilityLabel(strings().chatListFilterEditFilters)

        updateLocalizationAndTheme(theme: theme)
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = theme as! TelegramPresentationTheme
        edit.set(image: theme.icons.folders_sidebar_edit, for: .Normal)
        edit.borderColor = theme.colors.grayIcon.withAlphaComponent(0.1)
        needsLayout = true
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func rightMouseDown(with event: NSEvent) {
        super.rightMouseDown(with: event)
        let menu = ContextMenu()
        menu.addItem(ContextMenuItem(strings().navigationEdit, handler: { [weak self] in
            if let environment = self?.environment {
                let context = environment.context
                context.bindings.rootNavigation().push(ChatListFiltersListController(context: context, environment: environment))
            }
        }, itemImage: environment?.menuImage(.menu_edit)))
        AppMenu.show(menu: menu, event: event, for: self)
    }

    public override func layout() {
        super.layout()
        tableView.frame = NSMakeRect(0, 0, frame.width, frame.height - 50)
        edit.frame = NSMakeRect(0, frame.height - 50, frame.width, 50)
        edit.border = tableView.frame.height < tableView.documentSize.height ? [.Top] : []
    }
}

enum LeftSibarBarEntry : Comparable, Identifiable {
    static func < (lhs: LeftSibarBarEntry, rhs: LeftSibarBarEntry) -> Bool {
        return lhs.index < rhs.index
    }
    case topOffset
    case folder(index: Int, selected: Bool, filter: ChatListFilter, unreadCount: Int, hasUnmutedUnread: Bool, hideUnreadCounters: Bool)

    var stableId: Int32 {
        switch self {
        case .topOffset:
            return -2
        case let .folder(_, _, filter, _, _, _):
            return filter.sidebarId
        }
    }

    var index: Int {
        switch self {
        case .topOffset:
            return -1
        case let .folder(index, _, _, _, _, _):
            return index
        }
    }

    fileprivate func item(_ arguments: LeftSidebarArguments, initialSize: NSSize) -> TableRowItem {
        switch self {
        case let .folder(_, selected, filter, unreadCount, hasUnmutedUnread, hideUnreadCounters):
            return LeftSidebarFolderItem(initialSize, context: arguments.context, environment: arguments.environment, folder: filter, selected: selected, unreadCount: unreadCount, hasUnmutedUnread: hasUnmutedUnread, hideUnreadCounters: hideUnreadCounters, callback: arguments.callback, menuItems: arguments.menuItems)
        case .topOffset:
            return GeneralRowItem(initialSize, height: 30, stableId: stableId, backgroundColor: .clear)
        }
    }
}

func leftSidebarEntries(_ filterData: SidebarState, _ badges: ChatListFilterBadges) -> [LeftSibarBarEntry] {
    return leftSidebarEntries(filterData, badgeForFilter: { filter in
        badges.count(for: filter).map { ($0.count, $0.hasUnmutedUnread) }
    })
}

func leftSidebarEntries(_ filterData: SidebarState, badgeForFilter: (ChatListFilter) -> (count: Int, hasUnmutedUnread: Bool)?) -> [LeftSibarBarEntry] {
    var index: Int = 1

    var entries:[LeftSibarBarEntry] = []
    entries.append(.topOffset)

    for filter in filterData.tabs {
        let badge = badgeForFilter(filter)
        entries.append(.folder(index: index, selected: filter.sidebarId == filterData.selectedFilterId, filter: filter, unreadCount: badge?.count ?? 0, hasUnmutedUnread: badge?.hasUnmutedUnread ?? false, hideUnreadCounters: filterData.hideUnreadCounters))
        index += 1
    }

    return entries
}

fileprivate func prepareTransition(left:[AppearanceWrapperEntry<LeftSibarBarEntry>], right: [AppearanceWrapperEntry<LeftSibarBarEntry>], initialSize:NSSize, arguments:LeftSidebarArguments) -> TableUpdateTransition {

    let (removed, inserted, updated) = proccessEntriesWithoutReverse(left, right: right) { entry -> TableRowItem in
        return entry.entry.item(arguments, initialSize: initialSize)
    }

    return TableUpdateTransition(deleted: removed, inserted: inserted, updated: updated, animated: true)
}

public final class LeftSidebarController: SidebarViewController<LeftSidebarView> {

    let filterData: Signal<SidebarState, NoError>
    private let badges: Signal<ChatListFilterBadges, NoError>

    private let disposable = MetaDisposable()
    private var visibleFilters: [ChatListFilter] = []
    private var filtersAtReorderStart: [ChatListFilter] = []

    public init(_ context: any AccountContextProtocol, environment: SidebarUIEnvironment, filterData: Signal<SidebarState, NoError>, badges: Signal<ChatListFilterBadges, NoError>) {
        self.filterData = filterData
        self.badges = badges
        super.init(context, environment: environment)
        self.bar = .init(height: 0)
        self.insets = LeftSidebarView.inset
    }

    deinit {
        disposable.dispose()
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        genericView.updateLocalizationAndTheme(theme: theme)
    }

    public override var backdorColor: NSColor {
        return .clear
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        let context = self.context
        let environment = self.environment

        genericView.environment = environment

        let arguments = LeftSidebarArguments(context: context, environment: environment, callback: { filter in
            environment.navigateToFilter(filter.sidebarId)

        }, menuItems: { filter, unreadCount, allMuted in
            return filterContextMenuItems(filter, unreadCount: unreadCount, includeAllMuted: allMuted, context: context, environment: environment)
        })
        let initialSize = self.atomicSize

        let previous: Atomic<[AppearanceWrapperEntry<LeftSibarBarEntry>]> = Atomic(value: [])

        genericView.edit.set(handler: { _ in
            if let controller = context.bindings.rootNavigation().controller as? InputDataController {
                if controller.identifier == "filters" {
                    return
                }
            }
            context.bindings.rootNavigation().push(ChatListFiltersListController(context: context, environment: environment))
        }, for: .Click)


        let signal: Signal<(TableUpdateTransition, [ChatListFilter]), NoError> = combineLatest(queue: prepareQueue, filterData, badges, appearanceSignal) |> map { filterData, badges, appearance in
            let entries = leftSidebarEntries(filterData, badges).map { AppearanceWrapperEntry.init(entry: $0, appearance: appearance) }
            return (prepareTransition(left: previous.swap(entries), right: entries, initialSize: initialSize.with { $0 }, arguments: arguments), filterData.tabs)
        } |> deliverOnMainQueue

        self.genericView.tableView.alwaysOpenRowsOnMouseUp = true

        disposable.set(signal.start(next: { [weak self] transition, visible in

            guard let `self` = self else {
                return
            }
            self.visibleFilters = visible
            self.genericView.tableView.merge(with: transition)
            self.genericView.updateLocalizationAndTheme(theme: theme)
            self.readyOnce()

            let includesFixedAllChats = !context.isPremium && visible.first == .allChats
            let range = sidebarResortRange(rowCount: self.genericView.tableView.count, isPremium: !includesFixedAllChats)
            if range.length < 2 {
                self.genericView.tableView.resortController = nil
            } else if self.genericView.tableView.resortController?.resortRange != range {
                let resortController = TableResortController(resortRange: range, start: { [weak self] _ in
                    guard let self else {
                        return
                    }
                    self.filtersAtReorderStart = context.isPremium ? self.visibleFilters : self.visibleFilters.filter { $0 != .allChats }
                }, resort: { _ in }, complete: { [weak self] from, to in
                    guard let self else {
                        return
                    }
                    let visible = self.filtersAtReorderStart
                    self.filtersAtReorderStart = []
                    _ = context.engine.peers.updateChatListFiltersInteractively { filters in
                        return reorderingVisibleChatListFilters(filters, visible: visible, from: from - range.location, to: to - range.location)
                    }.start()
                })
                resortController.completeDelay = 0
                self.genericView.tableView.resortController = resortController
            }
        }))
    }
}

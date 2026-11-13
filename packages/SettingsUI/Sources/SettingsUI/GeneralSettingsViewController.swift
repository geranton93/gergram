import Cocoa
import TGUIKit
import TelegramCore
import InAppSettings
import SwiftSignalKit
import Postbox
import Localization
import ColorPalette
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AlertsUI
import LocalAnimations
import TelegramIconsTheme
import FoundationUtils
import TelegramMediaUtils
import AppAnalytics

private func profilePeerIdFormatTitle(_ format: ProfilePeerIdFormat) -> String {
    switch format {
    case .telegramAPI:
        return "Telegram API"
    case .botAPI:
        return "Bot API"
    }
}

private enum GeneralSettingsEntry : Comparable, Identifiable {
    static let zalgoFilterStableId = 32
    static let hideChatListStoriesStableId = 35

    case section(sectionId:Int)
    case header(sectionId: Int, uniqueId:Int, text:String)
    case liteMode(sectionId:Int, enabled: Bool, viewType: GeneralViewType)
    case checkSpellingWhileTyping(sectionId:Int, enabled: Bool, key: String, viewType: GeneralViewType)
    case checkGrammarWithSpelling(sectionId:Int, enabled: Bool, key: String, viewType: GeneralViewType)
    case correctSpellingAutomatically(sectionId:Int, enabled: Bool, key: String, viewType: GeneralViewType)
    case inAppSounds(sectionId:Int, enabled: Bool, viewType: GeneralViewType)
    case shortcuts(sectionId: Int, viewType: GeneralViewType)
    case enterBehavior(sectionId:Int, enabled: Bool, viewType: GeneralViewType)
    case cmdEnterBehavior(sectionId:Int, enabled: Bool, viewType: GeneralViewType)
    case emojiReplacements(sectionId:Int, enabled: Bool, viewType: GeneralViewType)
    case predictEmoji(sectionId:Int, enabled: Bool, viewType: GeneralViewType)
    case bigEmoji(sectionId:Int, enabled: Bool, viewType: GeneralViewType)
    case statusBar(sectionId:Int, enabled: Bool, viewType: GeneralViewType)
    case showCallsTab(sectionId:Int, enabled: Bool, viewType: GeneralViewType)
    case showContactsTab(sectionId:Int, enabled: Bool, viewType: GeneralViewType)
    case enableRFTCopy(sectionId:Int, enabled: Bool, viewType: GeneralViewType)
    case sendLargePhotos(sectionId:Int, enabled: Bool, viewType: GeneralViewType)
    case acceptSecretChats(sectionId:Int, enabled: Bool, viewType: GeneralViewType)
    case forceTouchReply(sectionId:Int, enabled: Bool, viewType: GeneralViewType)
    case forceTouchEdit(sectionId:Int, enabled: Bool, viewType: GeneralViewType)
    case forceTouchForward(sectionId:Int, enabled: Bool, viewType: GeneralViewType)
    case forceTouchReact(sectionId:Int, enabled: Bool, viewType: GeneralViewType)
    case forceTouchPreviewMedia(sectionId:Int, enabled: Bool, viewType: GeneralViewType)
    case callSettings(sectionId:Int, enabled: Bool, viewType: GeneralViewType)
    case previewChats(sectionId:Int, enabled: Bool, viewType: GeneralViewType)
    case previewChatsInfo(sectionId:Int)
    case showProfileId(sectionId:Int, enabled: Bool, viewType: GeneralViewType)
    case profileIdFormat(sectionId: Int, format: ProfilePeerIdFormat)
    case collapseChannelRecommendations(sectionId: Int, enabled: Bool)
    case hideSimilarChannelsTab(sectionId: Int, enabled: Bool)
    case disableGlobalPeerSearch(sectionId: Int, enabled: Bool)
    case hideChatListStories(sectionId: Int, enabled: Bool)
    case showMessageTimestampSeconds(sectionId: Int, enabled: Bool)
    case filterZalgoText(sectionId: Int, enabled: Bool)
    case messageContextMenu(sectionId: Int)
    case miniAppWindowSize(sectionId: Int)
    public var stableId: Int {
        switch self {
        case let .header(_, uniqueId, _):
            return uniqueId
        case .liteMode:
            return 1
        case .checkSpellingWhileTyping:
            return 2
        case .checkGrammarWithSpelling:
            return 3
        case .correctSpellingAutomatically:
            return 4
        case .emojiReplacements:
            return 6
        case .predictEmoji:
            return 7
        case .bigEmoji:
            return 8
        case .showCallsTab:
            return 9
        case .showContactsTab:
            return 5
        case .statusBar:
            return 10
        case .inAppSounds:
            return 11
        case .shortcuts:
            return 12
        case .enableRFTCopy:
            return 13
        case .sendLargePhotos:
            return 14
        case .acceptSecretChats:
            return 15
        case .forceTouchReply:
            return 16
        case .forceTouchEdit:
            return 17
        case .forceTouchForward:
            return 18
        case .forceTouchPreviewMedia:
            return 19
        case .forceTouchReact:
            return 20
        case .enterBehavior:
            return 21
        case .cmdEnterBehavior:
            return 22
        case .callSettings:
            return 23
        case .previewChats:
            return 24
        case .showProfileId:
            return 25
        case .previewChatsInfo:
            return 26
        case .profileIdFormat:
            return 27
        case .collapseChannelRecommendations:
            return 28
        case .hideSimilarChannelsTab:
            return 29
        case .disableGlobalPeerSearch:
            return 30
        case .hideChatListStories:
            return Self.hideChatListStoriesStableId
        case .showMessageTimestampSeconds:
            return 31
        case .filterZalgoText:
            return Self.zalgoFilterStableId
        case .messageContextMenu:
            return 33
        case .miniAppWindowSize:
            return 34
        case let .section(id):
            return (id + 1) * 1000 - id
        }
    }
    
    public var sortIndex:Int {
        switch self {
        case let .header(sectionId, _, _):
            return (sectionId * 1000) + stableId
        case let .liteMode(sectionId, _, _):
            return (sectionId * 1000) + stableId
        case let .checkSpellingWhileTyping(sectionId, _, _, _):
            return (sectionId * 1000) + stableId
        case let .checkGrammarWithSpelling(sectionId, _, _, _):
            return (sectionId * 1000) + stableId
        case let .correctSpellingAutomatically(sectionId, _, _, _):
            return (sectionId * 1000) + stableId
        case let .showCallsTab(sectionId, _, _), let .showContactsTab(sectionId, _, _):
            return (sectionId * 1000) + stableId
        case let .enableRFTCopy(sectionId, _, _):
            return (sectionId * 1000) + stableId
        case let .sendLargePhotos(sectionId, _, _):
            return (sectionId * 1000) + stableId
        case let .acceptSecretChats(sectionId, _, _):
            return (sectionId * 1000) + stableId
        case let .inAppSounds(sectionId, _, _):
            return (sectionId * 1000) + stableId
        case let .shortcuts(sectionId, _):
            return (sectionId * 1000) + stableId
        case let .emojiReplacements(sectionId, _, _):
            return (sectionId * 1000) + stableId
        case let .predictEmoji(sectionId, _, _):
            return (sectionId * 1000) + stableId
        case let .bigEmoji(sectionId, _, _):
            return (sectionId * 1000) + stableId
        case let .statusBar(sectionId, _, _):
            return (sectionId * 1000) + stableId
        case let .enterBehavior(sectionId, _, _):
            return (sectionId * 1000) + stableId
        case let .cmdEnterBehavior(sectionId, _, _):
            return (sectionId * 1000) + stableId
        case let .forceTouchReply(sectionId, _, _):
            return (sectionId * 1000) + stableId
        case let .forceTouchEdit(sectionId, _, _):
            return (sectionId * 1000) + stableId
        case let .forceTouchForward(sectionId, _, _):
            return (sectionId * 1000) + stableId
        case let .forceTouchReact(sectionId, _, _):
            return (sectionId * 1000) + stableId
        case let .forceTouchPreviewMedia(sectionId, _, _):
            return (sectionId * 1000) + stableId
        case let .callSettings(sectionId, _, _):
            return (sectionId * 1000) + stableId
        case let .previewChats(sectionId, _, _):
            return (sectionId * 1000) + stableId
        case let .previewChatsInfo(sectionId):
            return (sectionId * 1000) + stableId
        case let .showProfileId(sectionId, _, _):
            return (sectionId * 1000) + stableId
        case let .profileIdFormat(sectionId, _):
            return (sectionId * 1000) + stableId
        case let .collapseChannelRecommendations(sectionId, _), let .hideSimilarChannelsTab(sectionId, _), let .disableGlobalPeerSearch(sectionId, _), let .hideChatListStories(sectionId, _), let .showMessageTimestampSeconds(sectionId, _), let .filterZalgoText(sectionId, _), let .messageContextMenu(sectionId), let .miniAppWindowSize(sectionId):
            return (sectionId * 1000) + stableId
        case let .section(id):
            return (id + 1) * 1000 - id
        }
    }
    
    public func item(_ arguments:GeneralSettingsArguments, initialSize:NSSize) -> TableRowItem {
        switch self {
        case .section:
            return GeneralRowItem(initialSize, height: 20, stableId: stableId, viewType: .separator)
        case let .header(sectionId: _, uniqueId: _, text: text):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: text, viewType: .textTopItem)
        case let .liteMode(_, enabled: enabled, viewType):
            return  GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().generalSettingsLiteMode, type: .nextContext(enabled ? strings().liteModeEnabled : strings().liteModeDisabled), viewType: viewType, action: {
                arguments.openLiteMode()
            })
        case let .checkSpellingWhileTyping(_, enabled, key, viewType):
            return  GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().generalSettingsSpellingCheckWhileTyping, type: .switchable(enabled), viewType: viewType, action: {
                arguments.toggleSpellingKey(key)
            })
        case let .checkGrammarWithSpelling(_, enabled, key, viewType):
            return  GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().generalSettingsSpellingCheckGrammarSpelling, type: .switchable(enabled), viewType: viewType, action: {
                arguments.toggleSpellingKey(key)
            })
        case let .correctSpellingAutomatically(_, enabled, key, viewType):
            return  GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().generalSettingsSpellingCheckSpellingAutomatically, type: .switchable(enabled), viewType: viewType, action: {
                arguments.toggleSpellingKey(key)
            })
        case let .showCallsTab(sectionId: _, enabled: enabled, viewType):
            return  GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().generalSettingsShowCallsTab, type: .switchable(enabled), viewType: viewType, action: {
                arguments.toggleCallsTab(!enabled)
            })
        case let .showContactsTab(sectionId: _, enabled: enabled, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().generalSettingsShowContactsTab, type: .switchable(enabled), viewType: viewType, action: {
                arguments.toggleContactsTab(!enabled)
            })
        case let .enableRFTCopy(sectionId: _, enabled, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().generalSettingsCopyRTF, type: .switchable(enabled), viewType: viewType, action: {
                arguments.toggleRTFEnabled(!enabled)
            })
        case let .sendLargePhotos(sectionId: _, enabled, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().generalSettingsSendLargePhotos, type: .switchable(enabled), viewType: viewType, action: {
                arguments.toggleLargePhotos(!enabled)
            })
        case let .acceptSecretChats(_, enabled, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().generalSettingsAcceptSecretChats, type: .switchable(enabled), viewType: viewType, action: {
                arguments.acceptSecretChats(!enabled)
            })
        case let .inAppSounds(sectionId: _, enabled, viewType):
            return  GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().generalSettingsInAppSounds, type: .switchable(enabled), viewType: viewType, action: {
                arguments.toggleInAppSounds(!enabled)
            })
        case let .shortcuts(_, viewType):
            return  GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().generalSettingsShortcuts, type: .nextContext("⌘ + ?"), viewType: viewType, action: {
                arguments.openShortcuts()
            })
        case let .emojiReplacements(sectionId: _, enabled, viewType):
            return  GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().generalSettingsEmojiReplacements, type: .switchable(enabled), viewType: viewType, action: {
                arguments.toggleEmojiReplacements(!enabled)
            })
        case let .predictEmoji(sectionId: _, enabled, viewType):
            return  GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().generalSettingsEmojiPrediction, type: .switchable(enabled), viewType: viewType, action: {
                arguments.toggleEmojiPrediction(!enabled)
            })
        case let .bigEmoji(sectionId: _, enabled, viewType):
            return  GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().generalSettingsBigEmoji, type: .switchable(enabled), viewType: viewType, action: {
                arguments.toggleBigEmoji(!enabled)
            })
        case let .statusBar(sectionId: _, enabled, viewType):
            return  GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().generalSettingsStatusBarItem, type: .switchable(enabled), viewType: viewType, action: {
                arguments.toggleStatusBar(!enabled)
            })
        case let .enterBehavior(sectionId: _, enabled, viewType):
            return GeneralInteractedRowItem(initialSize, name: strings().generalSettingsSendByEnter, type: .selectable(enabled), viewType: viewType, action: {
                arguments.toggleInput(.enter)
            })
        case let .cmdEnterBehavior(sectionId: _, enabled, viewType):
            return GeneralInteractedRowItem(initialSize, name: strings().generalSettingsSendByCmdEnter, type: .selectable(enabled), viewType: viewType, action: {
                arguments.toggleInput(.cmdEnter)
            })
        case let .forceTouchEdit(sectionId: _, enabled, viewType):
            return GeneralInteractedRowItem(initialSize, name: strings().generalSettingsForceTouchEdit, type: .selectable(enabled), viewType: viewType, action: {
                arguments.toggleForceTouchAction(.edit)
            })
        case let .forceTouchReply(sectionId: _, enabled, viewType):
            return GeneralInteractedRowItem(initialSize, name: strings().generalSettingsForceTouchReply, type: .selectable(enabled), viewType: viewType, action: {
               arguments.toggleForceTouchAction(.reply)
            })
        case let .forceTouchForward(sectionId: _, enabled, viewType):
            return GeneralInteractedRowItem(initialSize, name: strings().generalSettingsForceTouchForward, type: .selectable(enabled), viewType: viewType, action: {
                arguments.toggleForceTouchAction(.forward)
            })
        case let .forceTouchReact(sectionId: _, enabled, viewType):
            return GeneralInteractedRowItem(initialSize, name: strings().generalSettingsForceTouchReact, type: .selectable(enabled), viewType: viewType, action: {
                arguments.toggleForceTouchAction(.react)
            })
        case let .forceTouchPreviewMedia(sectionId: _, enabled, viewType):
            return GeneralInteractedRowItem(initialSize, name: strings().generalSettingsForceTouchPreviewMedia, type: .selectable(enabled), viewType: viewType, action: {
                arguments.toggleForceTouchAction(.previewMedia)
            })
        case let .callSettings(_, _, viewType):
            return GeneralInteractedRowItem(initialSize, name: strings().generalSettingsCallSettingsText, type: .next, viewType: viewType, action: {
                arguments.callSettings()
            })
        case let .showProfileId(_, value, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().generalSettingsShowProfileIdText, type: .switchable(value), viewType: viewType, action: arguments.showProfileId)
        case let .profileIdFormat(_, format):
            let options = ProfilePeerIdFormat.allCases.map { option in
                ContextMenuItem(profilePeerIdFormatTitle(option), handler: {
                    FastSettings.profilePeerIdFormat = option
                }, itemImage: option == format ? MenuAnimation.menu_check_selected.value : nil)
            }
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().generalSettingsShowProfileIdFormat, type: .contextSelector(profilePeerIdFormatTitle(format), options), viewType: .lastItem)
        case let .collapseChannelRecommendations(_, enabled):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().generalSettingsSimilarChannelsCollapse, type: .switchable(enabled), viewType: .firstItem, action: {
                FastSettings.collapseChannelRecommendations.toggle()
            })
        case let .hideSimilarChannelsTab(_, enabled):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().generalSettingsSimilarChannelsHideTab, type: .switchable(enabled), viewType: .innerItem, action: {
                FastSettings.hideSimilarChannelsTab.toggle()
            })
        case let .disableGlobalPeerSearch(_, disabled):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: localizedString("Gergram.Search.DisableGlobalPeerSearch"), type: .switchable(disabled), viewType: .innerItem, action: {
                _ = updateAdditionalSettingsInteractively(accountManager: arguments.context.sharedContext.accountManager) { settings in
                    settings.withUpdatedDisableGlobalPeerSearch(!settings.disableGlobalPeerSearch)
                }.startStandalone()
            }, autoswitch: false)
        case let .hideChatListStories(_, hidden):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: localizedString("Gergram.Stories.HideInChatList"), type: .switchable(hidden), viewType: .lastItem, action: {
                _ = updateAdditionalSettingsInteractively(accountManager: arguments.context.sharedContext.accountManager) { settings in
                    settings.withUpdatedHideChatListStories(!settings.hideChatListStories)
                }.startStandalone()
            }, autoswitch: false)
        case let .showMessageTimestampSeconds(_, enabled):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().generalSettingsShowMessageTimestampSeconds, type: .switchable(enabled), viewType: .firstItem, action: {
                FastSettings.showMessageTimestampSeconds.toggle()
            })
        case let .filterZalgoText(_, enabled):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: localizedString("Gergram.Chat.FilterZalgoText"), type: .switchable(enabled), viewType: .innerItem, action: {
                FastSettings.filterZalgoText.toggle()
            })
        case .messageContextMenu:
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: localizedString("Gergram.Chat.MenuSettings"), type: .next, viewType: .lastItem, action: {
                arguments.context.bindings.rootNavigation().push(messageContextMenuSettingsController())
            })
        case .miniAppWindowSize:
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: localizedString("Gergram.MiniApp.WindowSize"), type: .next, viewType: .singleItem, action: {
                arguments.context.bindings.rootNavigation().push(miniAppWindowSizeSettingsController())
            })
        case let .previewChats(_, value, viewType):
            return GeneralInteractedRowItem(initialSize, name: strings().generalSettingsPreviewChatsText, type: .switchable(value), viewType: viewType, action: arguments.togglePreviewChat)
        case .previewChatsInfo:
            return GeneralTextRowItem(initialSize, stableId: stableId, text: strings().generalSettingsPreviewChatsInfo, viewType: .textBottomItem)
        }
    }
}
private func <(lhs: GeneralSettingsEntry, rhs: GeneralSettingsEntry) -> Bool {
    return lhs.sortIndex < rhs.sortIndex
}

private final class GeneralSettingsArguments {
    public let context:any AccountContextProtocol
    public let toggleCallsTab:(Bool) -> Void
    public let toggleContactsTab:(Bool) -> Void
    public let toggleInAppKeys:(Bool) -> Void
    public let toggleInput:(SendingType)-> Void
    public let toggleInAppSounds:(Bool) -> Void
    public let toggleEmojiReplacements:(Bool) -> Void
    public let toggleForceTouchAction:(ForceTouchAction) -> Void
	public let toggleInstantViewScrollBySpace:(Bool) -> Void
    public let toggleAutoplayGifs:(Bool) -> Void
    public let toggleEmojiPrediction: (Bool)->Void
    public let toggleBigEmoji: (Bool) -> Void
    public let toggleStatusBar: (Bool) -> Void
    public let toggleRTFEnabled: (Bool) -> Void
    public let toggleLargePhotos: (Bool) -> Void
    public let acceptSecretChats:(Bool)->Void
    public let toggleWorkMode:(Bool)->Void
    public let openShortcuts: ()->Void
    public let callSettings: ()->Void
    public let openLiteMode: ()->Void
    public let toggleSpellingKey:(String)->Void
    public let showProfileId:()->Void
    public let togglePreviewChat:()->Void
    public init(context:any AccountContextProtocol, toggleCallsTab:@escaping(Bool)-> Void, toggleContactsTab:@escaping(Bool)-> Void, toggleInAppKeys: @escaping(Bool) -> Void, toggleInput: @escaping(SendingType)-> Void, toggleInAppSounds: @escaping (Bool) -> Void, toggleEmojiReplacements:@escaping(Bool) -> Void, toggleForceTouchAction: @escaping(ForceTouchAction)->Void, toggleInstantViewScrollBySpace: @escaping(Bool)->Void, toggleAutoplayGifs:@escaping(Bool) -> Void, toggleEmojiPrediction: @escaping(Bool) -> Void, toggleBigEmoji: @escaping(Bool) -> Void, toggleStatusBar: @escaping(Bool) -> Void, toggleRTFEnabled: @escaping(Bool)->Void, toggleLargePhotos: @escaping(Bool) -> Void, acceptSecretChats: @escaping(Bool)->Void, toggleWorkMode:@escaping(Bool)->Void, openShortcuts: @escaping()->Void, callSettings: @escaping() ->Void, openLiteMode: @escaping()->Void, toggleSpellingKey:@escaping(String)->Void, showProfileId:@escaping()->Void, togglePreviewChat:@escaping()->Void) {
        self.context = context
        self.toggleCallsTab = toggleCallsTab
        self.toggleContactsTab = toggleContactsTab
        self.toggleInAppKeys = toggleInAppKeys
        self.toggleInput = toggleInput
        self.toggleInAppSounds = toggleInAppSounds
        self.toggleEmojiReplacements = toggleEmojiReplacements
        self.toggleForceTouchAction = toggleForceTouchAction
		self.toggleInstantViewScrollBySpace = toggleInstantViewScrollBySpace
        self.toggleAutoplayGifs = toggleAutoplayGifs
        self.toggleEmojiPrediction = toggleEmojiPrediction
        self.toggleBigEmoji = toggleBigEmoji
        self.toggleStatusBar = toggleStatusBar
        self.toggleRTFEnabled = toggleRTFEnabled
        self.acceptSecretChats = acceptSecretChats
        self.toggleWorkMode = toggleWorkMode
        self.openShortcuts = openShortcuts
        self.callSettings = callSettings
        self.openLiteMode = openLiteMode
        self.toggleSpellingKey = toggleSpellingKey
        self.showProfileId = showProfileId
        self.togglePreviewChat = togglePreviewChat
        self.toggleLargePhotos = toggleLargePhotos
    }
   
}

private func generalSettingsEntries(arguments:GeneralSettingsArguments, baseSettings: BaseApplicationSettings, appearance: Appearance, launchSettings: LaunchSettings, secretChatSettings: SecretChatSettings, additionalSettings: AdditionalSettings, peerIdFormat: ProfilePeerIdFormat?, collapseChannelRecommendations: Bool, hideSimilarChannelsTab: Bool, showMessageTimestampSeconds: Bool, filterZalgoText: Bool) -> [GeneralSettingsEntry] {
    var sectionId:Int = 1
    var entries:[GeneralSettingsEntry] = []
    
    var headerUnique:Int = -1
    
    entries.append(.section(sectionId: sectionId))
    sectionId += 1
    
    entries.append(.header(sectionId: sectionId, uniqueId: headerUnique, text: strings().generalSettingsEnergySaving))
    headerUnique -= 1
    
    entries.append(.liteMode(sectionId: sectionId, enabled: baseSettings.liteMode.enabled, viewType: .singleItem))
    
    entries.append(.section(sectionId: sectionId))
    sectionId += 1
    
    
    entries.append(.header(sectionId: sectionId, uniqueId: headerUnique, text: strings().generalSettingsSpellingTitle))
    headerUnique -= 1
    
    let key1 = "ContinuousSpellCheckingEnabled" + "TGGrowingTextView"
    let key2 = "GrammarCheckingEnabled" + "TGGrowingTextView"
    let key3 = "AutomaticSpellingCorrectionEnabled" + "TGGrowingTextView"
    
    entries.append(.checkSpellingWhileTyping(sectionId: sectionId, enabled: UserDefaults.standard.bool(forKey: key1), key: key1, viewType: .firstItem))
    entries.append(.checkGrammarWithSpelling(sectionId: sectionId, enabled: UserDefaults.standard.bool(forKey: key2), key: key2, viewType: .innerItem))
    entries.append(.correctSpellingAutomatically(sectionId: sectionId, enabled: UserDefaults.standard.bool(forKey: key3), key: key3, viewType: .lastItem))
    
    entries.append(.section(sectionId: sectionId))
    sectionId += 1


    entries.append(.header(sectionId: sectionId, uniqueId: headerUnique, text: strings().generalSettingsEmoji))
    headerUnique -= 1
    entries.append(.emojiReplacements(sectionId: sectionId, enabled: FastSettings.isPossibleReplaceEmojies, viewType: .firstItem))
    if !baseSettings.predictEmoji {
        entries.append(.predictEmoji(sectionId: sectionId, enabled: baseSettings.predictEmoji, viewType: .innerItem))
    }
    entries.append(.bigEmoji(sectionId: sectionId, enabled: baseSettings.bigEmoji, viewType: .lastItem))

    

    
    entries.append(.section(sectionId: sectionId))
    sectionId += 1
    
    entries.append(.header(sectionId: sectionId, uniqueId: headerUnique, text: strings().generalSettingsInterfaceHeader))
    headerUnique -= 1
    entries.append(.showContactsTab(sectionId: sectionId, enabled: baseSettings.showContactsTab, viewType: .firstItem))
    entries.append(.showCallsTab(sectionId: sectionId, enabled: baseSettings.showCallsTab, viewType: .innerItem))
    entries.append(.statusBar(sectionId: sectionId, enabled: baseSettings.statusBar, viewType: .innerItem))
    entries.append(.previewChats(sectionId: sectionId, enabled: additionalSettings.previewChats, viewType: .lastItem))
    entries.append(.previewChatsInfo(sectionId: sectionId))

    
    entries.append(.section(sectionId: sectionId))
    sectionId += 1
    
    entries.append(.header(sectionId: sectionId, uniqueId: headerUnique, text: strings().generalSettingsShortcutsHeader))
    headerUnique -= 1
    entries.append(.shortcuts(sectionId: sectionId, viewType: .singleItem))


	
    entries.append(.section(sectionId: sectionId))
    sectionId += 1
    
    entries.append(.header(sectionId: sectionId, uniqueId: headerUnique, text: strings().generalSettingsAdvancedHeader))
    headerUnique -= 1
    entries.append(.enableRFTCopy(sectionId: sectionId, enabled: FastSettings.enableRTF, viewType: .firstItem))
    entries.append(.sendLargePhotos(sectionId: sectionId, enabled: FastSettings.sendLargePhotos, viewType: .lastItem))
    
    entries.append(.section(sectionId: sectionId))
    sectionId += 1
    
    entries.append(.header(sectionId: sectionId, uniqueId: headerUnique, text: strings().generalSettingsForceTouchHeader))
    headerUnique -= 1
    
    entries.append(.forceTouchReply(sectionId: sectionId, enabled: FastSettings.forceTouchAction == .reply, viewType: .firstItem))
    entries.append(.forceTouchEdit(sectionId: sectionId, enabled: FastSettings.forceTouchAction == .edit, viewType: .innerItem))
    entries.append(.forceTouchForward(sectionId: sectionId, enabled: FastSettings.forceTouchAction == .forward, viewType: .innerItem))
    entries.append(.forceTouchReact(sectionId: sectionId, enabled: FastSettings.forceTouchAction == .react, viewType: .lastItem))

    entries.append(.section(sectionId: sectionId))
    sectionId += 1
    
    entries.append(.header(sectionId: sectionId, uniqueId: headerUnique, text: strings().generalSettingsInputSettings))
    headerUnique -= 1
    entries.append(.enterBehavior(sectionId: sectionId, enabled: FastSettings.sendingType == .enter, viewType: .firstItem))
    entries.append(.cmdEnterBehavior(sectionId: sectionId, enabled: FastSettings.sendingType == .cmdEnter, viewType: .lastItem))
    
    entries.append(.section(sectionId: sectionId))
    sectionId += 1

    
    entries.append(.header(sectionId: sectionId, uniqueId: headerUnique, text: strings().generalSettingsCallSettingsHeader))
    headerUnique -= 1
    
    entries.append(.callSettings(sectionId: sectionId, enabled: true, viewType: .singleItem))

    entries.append(.section(sectionId: sectionId))
    sectionId += 1
    
    entries.append(.showProfileId(sectionId: sectionId, enabled: peerIdFormat != nil, viewType: peerIdFormat == nil ? .singleItem : .firstItem))
    if let peerIdFormat {
        entries.append(.profileIdFormat(sectionId: sectionId, format: peerIdFormat))
    }

    entries.append(.section(sectionId: sectionId))
    sectionId += 1
    entries.append(.collapseChannelRecommendations(sectionId: sectionId, enabled: collapseChannelRecommendations))
    entries.append(.hideSimilarChannelsTab(sectionId: sectionId, enabled: hideSimilarChannelsTab))
    entries.append(.disableGlobalPeerSearch(sectionId: sectionId, enabled: additionalSettings.disableGlobalPeerSearch))
    entries.append(.hideChatListStories(sectionId: sectionId, enabled: additionalSettings.hideChatListStories))

    entries.append(.section(sectionId: sectionId))
    sectionId += 1
    entries.append(.showMessageTimestampSeconds(sectionId: sectionId, enabled: showMessageTimestampSeconds))
    entries.append(.filterZalgoText(sectionId: sectionId, enabled: filterZalgoText))
    entries.append(.messageContextMenu(sectionId: sectionId))

    entries.append(.section(sectionId: sectionId))
    sectionId += 1
    entries.append(.miniAppWindowSize(sectionId: sectionId))

    entries.append(.section(sectionId: sectionId))
    return entries
}

private func prepareEntries(left: [AppearanceWrapperEntry<GeneralSettingsEntry>], right: [AppearanceWrapperEntry<GeneralSettingsEntry>], arguments: GeneralSettingsArguments, initialSize: NSSize) -> TableUpdateTransition {
    let (removed, inserted, updated)  = proccessEntriesWithoutReverse(left, right: right) { entry -> TableRowItem in
        return entry.entry.item(arguments, initialSize: initialSize)
    }
    
    return TableUpdateTransition(deleted: removed, inserted: inserted, updated: updated, animated: true)
}

open class GeneralSettingsViewController<Context: AccountContextProtocol>: TableViewController<Context> {

    open override var defaultBarTitle: String {
        return strings().telegramGeneralSettingsViewController
    }

    
    private let disposable = MetaDisposable()
    private var focusedSettingId: Int?
    func focusOnZalgoFilter() {
        focusedSettingId = GeneralSettingsEntry.zalgoFilterStableId
    }

    func focusOnHideChatListStories() {
        focusedSettingId = GeneralSettingsEntry.hideChatListStoriesStableId
    }
    open override var removeAfterDisapper:Bool {
        return false
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        
       
        let context = self.context
        let inputPromise:ValuePromise<SendingType> = ValuePromise(FastSettings.sendingType, ignoreRepeated: true)
        
        let forceTouchPromise:ValuePromise<ForceTouchAction> = ValuePromise(FastSettings.forceTouchAction, ignoreRepeated: true)
        
        let arguments = GeneralSettingsArguments(context: context, toggleCallsTab: { enable in
            _ = updateBaseAppSettingsInteractively(accountManager: context.sharedContext.accountManager, { settings -> BaseApplicationSettings in
                return settings.withUpdatedShowCallsTab(enable)
            }).start()
        }, toggleContactsTab: { enable in
            _ = updateBaseAppSettingsInteractively(accountManager: context.sharedContext.accountManager, { settings -> BaseApplicationSettings in
                return settings.withUpdatedShowContactsTab(enable)
            }).start()
        }, toggleInAppKeys: { enable in
            _ = updateBaseAppSettingsInteractively(accountManager: context.sharedContext.accountManager, { settings -> BaseApplicationSettings in
                return settings.withUpdatedInAppKeyHandle(enable)
            }).start()
        }, toggleInput: { input in
            if FastSettings.sendingType != input {
                Analytics.shared.send(AnalyticsEvents.settingsChange(.chatSendWith(input == .cmdEnter ? .cmdEnter : .enter)))
            }
            FastSettings.changeSendingType(input)
            inputPromise.set(input)
        }, toggleInAppSounds: { enable in
            FastSettings.toggleInAppSouds(enable)
        }, toggleEmojiReplacements: { enable in
            FastSettings.toggleAutomaticReplaceEmojies(enable)
        }, toggleForceTouchAction: { action in
            FastSettings.toggleForceTouchAction(action)
            forceTouchPromise.set(action)
		}, toggleInstantViewScrollBySpace: { enable in
			FastSettings.toggleInstantViewScrollBySpace(enable)
        }, toggleAutoplayGifs: { enable in
            FastSettings.toggleAutoPlayGifs(enable)
        }, toggleEmojiPrediction: { enable in
            _ = updateBaseAppSettingsInteractively(accountManager: context.sharedContext.accountManager, { settings -> BaseApplicationSettings in
                return settings.withUpdatedPredictEmoji(enable)
            }).start()
        }, toggleBigEmoji: { enable in
            _ = updateBaseAppSettingsInteractively(accountManager: context.sharedContext.accountManager, { settings -> BaseApplicationSettings in
                return settings.withUpdatedBigEmoji(enable)
            }).start()
        }, toggleStatusBar: { enable in
            _ = updateBaseAppSettingsInteractively(accountManager: context.sharedContext.accountManager, { settings -> BaseApplicationSettings in
                return settings.withUpdatedStatusBar(enable)
            }).start()
        }, toggleRTFEnabled: { enable in
            FastSettings.enableRTF = enable
        }, toggleLargePhotos: { enable in
            FastSettings.sendLargePhotos(enable)
        }, acceptSecretChats: { enable in
            _ = context.account.postbox.transaction({ transaction -> Void in
                transaction.updatePreferencesEntry(key: PreferencesKeys.secretChatSettings, { _ in
                   return PreferencesEntry(SecretChatSettings(acceptOnThisDevice: enable))
                })
            }).start()
        }, toggleWorkMode: { value in
            
        }, openShortcuts: {
            context.bindings.rootNavigation().push(ShortcutListController(context: context))
        }, callSettings: {
            context.bindings.rootNavigation().push(SettingsNavigationHooks.shared.makeCallSettingsController(context))
        }, openLiteMode: {
            context.bindings.rootNavigation().push(LiteModeController(context: context))
        }, toggleSpellingKey: { key in
            UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
        }, showProfileId: {
            FastSettings.canViewPeerId = !FastSettings.canViewPeerId
        }, togglePreviewChat: {
            _ = updateAdditionalSettingsInteractively(accountManager: context.sharedContext.accountManager, {
                $0.withUpdatedPreviewChats(!$0.previewChats)
            }).startStandalone()
        })
        
        let initialSize = atomicSize
        
        let previos:Atomic<[AppearanceWrapperEntry<GeneralSettingsEntry>]> = Atomic(value: [])
        
        let baseSettingsSignal: Signal<BaseApplicationSettings, NoError> = .single(context.sharedContext.baseSettings) |> then(baseAppSettings(accountManager: context.sharedContext.accountManager))
        
        let signal = combineLatest(queue: prepareQueue, baseSettingsSignal, inputPromise.get(), forceTouchPromise.get(), appearanceSignal, appLaunchSettings(postbox: context.account.postbox), context.account.postbox.preferencesView(keys: [PreferencesKeys.secretChatSettings]), additionalSettings(accountManager: context.sharedContext.accountManager), FastSettings.profilePeerIdDisplay, FastSettings.collapseChannelRecommendationsSignal, FastSettings.hideSimilarChannelsTabSignal, FastSettings.showMessageTimestampSecondsSignal, FastSettings.filterZalgoTextSignal) |> map { settings, _, _, appearance, launchSettings, preferencesView, additionalSettings, peerIdFormat, collapseChannelRecommendations, hideSimilarChannelsTab, showMessageTimestampSeconds, filterZalgoText -> TableUpdateTransition in
            
            let baseSettings: BaseApplicationSettings = settings
            
            let secretChatSettings = preferencesView.values[PreferencesKeys.secretChatSettings]?.get(SecretChatSettings.self) ?? SecretChatSettings.defaultSettings
            
            let entries = generalSettingsEntries(arguments: arguments, baseSettings: baseSettings, appearance: appearance, launchSettings: launchSettings, secretChatSettings: secretChatSettings, additionalSettings: additionalSettings, peerIdFormat: peerIdFormat, collapseChannelRecommendations: collapseChannelRecommendations, hideSimilarChannelsTab: hideSimilarChannelsTab, showMessageTimestampSeconds: showMessageTimestampSeconds, filterZalgoText: filterZalgoText).map({AppearanceWrapperEntry(entry: $0, appearance: appearance)})
            let previous = previos.swap(entries)
            return prepareEntries(left: previous, right: entries, arguments: arguments, initialSize: initialSize.modify({$0}))
            
        } |> deliverOnMainQueue
        
        disposable.set(signal.start(next: { [weak self] transition in
            guard let self else {
                return
            }
            self.genericView.merge(with: transition)
            self.readyOnce()
            if let id = self.focusedSettingId {
                self.focusedSettingId = nil
                self.genericView.scroll(to: .center(id: id, innerId: nil, animated: true, focus: .init(focus: true), inset: 0))
            }
        }))
                
    }
    
    
    public func sendLogs() {
        
    }
    
    deinit {
        disposable.dispose()
    }

    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)        
    }
    

    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        window?.removeAllHandlers(for: self)
    }
   
}



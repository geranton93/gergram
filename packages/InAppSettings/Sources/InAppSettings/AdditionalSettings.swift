import Cocoa
import Postbox
import SwiftSignalKit
import TelegramCore


public struct AdditionalSettings: Codable, Equatable {
    public let useTouchId: Bool
    public let previewChats: Bool
    public let alwaysDarkMode: Bool?
    public let disableGlobalPeerSearch: Bool
    public let hideChatListStories: Bool
    public let hideProfileStories: Bool
    public static var defaultSettings: AdditionalSettings {
        return AdditionalSettings(useTouchId: false, previewChats: false, alwaysDarkMode: false)
    }
    
    public init(useTouchId: Bool, previewChats: Bool, alwaysDarkMode: Bool?, disableGlobalPeerSearch: Bool = false, hideChatListStories: Bool = false, hideProfileStories: Bool = false) {
        self.useTouchId = useTouchId
        self.previewChats = previewChats
        self.alwaysDarkMode = alwaysDarkMode
        self.disableGlobalPeerSearch = disableGlobalPeerSearch
        self.hideChatListStories = hideChatListStories
        self.hideProfileStories = hideProfileStories
    }
    
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        self.useTouchId = try container.decode(Bool.self, forKey: "ti")
        self.previewChats = try container.decodeIfPresent(Bool.self, forKey: "pc") ?? false
        self.alwaysDarkMode = try container.decodeIfPresent(Bool.self, forKey: "adm")
        self.disableGlobalPeerSearch = try container.decodeIfPresent(Bool.self, forKey: "dgps") ?? false
        self.hideChatListStories = try container.decodeIfPresent(Bool.self, forKey: "hcls") ?? false
        self.hideProfileStories = try container.decodeIfPresent(Bool.self, forKey: "hps") ?? false
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try container.encode(self.useTouchId, forKey: "ti")
        try container.encode(self.previewChats, forKey: "pc")
        try container.encodeIfPresent(self.alwaysDarkMode, forKey: "adm")
        try container.encode(self.disableGlobalPeerSearch, forKey: "dgps")
        try container.encode(self.hideChatListStories, forKey: "hcls")
        try container.encode(self.hideProfileStories, forKey: "hps")
    }
    
    
    public func withUpdatedTouchId(_ useTouchId: Bool) -> AdditionalSettings {
        return AdditionalSettings(useTouchId: useTouchId, previewChats: previewChats, alwaysDarkMode: alwaysDarkMode, disableGlobalPeerSearch: disableGlobalPeerSearch, hideChatListStories: hideChatListStories, hideProfileStories: hideProfileStories)
    }
    public func withUpdatedPreviewChats(_ previewChats: Bool) -> AdditionalSettings {
        return AdditionalSettings(useTouchId: useTouchId, previewChats: previewChats, alwaysDarkMode: alwaysDarkMode, disableGlobalPeerSearch: disableGlobalPeerSearch, hideChatListStories: hideChatListStories, hideProfileStories: hideProfileStories)
    }
    public func withUpdatedDisableGlobalPeerSearch(_ disabled: Bool) -> AdditionalSettings {
        return AdditionalSettings(useTouchId: useTouchId, previewChats: previewChats, alwaysDarkMode: alwaysDarkMode, disableGlobalPeerSearch: disabled, hideChatListStories: hideChatListStories, hideProfileStories: hideProfileStories)
    }
    public func withUpdatedHideChatListStories(_ hidden: Bool) -> AdditionalSettings {
        return AdditionalSettings(useTouchId: useTouchId, previewChats: previewChats, alwaysDarkMode: alwaysDarkMode, disableGlobalPeerSearch: disableGlobalPeerSearch, hideChatListStories: hidden, hideProfileStories: hideProfileStories)
    }
    public func withUpdatedHideProfileStories(_ hidden: Bool) -> AdditionalSettings {
        return AdditionalSettings(useTouchId: useTouchId, previewChats: previewChats, alwaysDarkMode: alwaysDarkMode, disableGlobalPeerSearch: disableGlobalPeerSearch, hideChatListStories: hideChatListStories, hideProfileStories: hidden)
    }
}

public func updateAdditionalSettingsInteractively(accountManager: AccountManager<TelegramAccountManagerTypes>, _ f: @escaping (AdditionalSettings) -> AdditionalSettings) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        transaction.updateSharedData(ApplicationSharedPreferencesKeys.additionalSettings, { entry in
            let currentSettings: AdditionalSettings
            if let entry = entry?.get(AdditionalSettings.self) {
                currentSettings = entry
            } else {
                currentSettings = AdditionalSettings.defaultSettings
            }
            return PreferencesEntry(f(currentSettings))
        })
    }
}

public func additionalSettings(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<AdditionalSettings, NoError> {
    return accountManager.sharedData(keys: [ApplicationSharedPreferencesKeys.additionalSettings]) |> map { view in
        return view.entries[ApplicationSharedPreferencesKeys.additionalSettings]?.get(AdditionalSettings.self) ?? AdditionalSettings.defaultSettings
    }
}


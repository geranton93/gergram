import Foundation
import InAppSettings
import SwiftSignalKit
import TGUIKit
import XCTest
@testable import SettingsUI

final class GergramAppearanceResetTests: XCTestCase {
    func testResetRestoresEveryAppearanceValueAndPreservesOtherDomains() throws {
        let name = "Gergram.ResetTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let initial = defaults.persistentDomain(forName: name) ?? [:]
        ChatEditedIndicatorPreferences(defaults: defaults).set(.hidden)
        XCTAssertTrue(ChatEditedIndicatorPreferences(defaults: defaults).setCustomText("revised"))
        ProfileJoinDatePreferences(defaults: defaults).setVisible(true)
        ChatWallpaperVisibilityPreferences(defaults: defaults).setHidden(true)
        ComposerEmojiHoverPreferences(defaults: defaults).setEnabled(false)
        ComposerBotCommandsPreferences(defaults: defaults).setHidden(true)
        ComposerGiftButtonPreferences(defaults: defaults).setHidden(true)
        ComposerAIToolsButtonPreferences(defaults: defaults).setHidden(true)
        StreamerModeMenuBarPreferences(defaults: defaults).setVisible(false)
        PremiumStatusVisibilityPreferences(defaults: defaults).setHidden(true)
        ChatReplyAppearancePreferences(defaults: defaults).setSimplified(true)
        ChatReactionVisibilityPreferences(defaults: defaults).setHiddenKinds(Set(ChatReactionVisibilityPreferences.ChatKind.allCases))
        MessageBubbleTailPreferences(defaults: defaults).setHidden(true)
        ChatMessageWidthPreferences(defaults: defaults).set(.wide)
        ChatMediaSpoilerPreferences(defaults: defaults).setEnabled(true)
        ChatMonospaceFontPreferences(defaults: defaults).set(.monaco)
        MessageBubbleRadiusPreferences(defaults: defaults).setRadius(0)
        SwitchAnimationPreferences(defaults: defaults).setEnabled(false)
        ProfileMusicCoverPreferences(defaults: defaults).setAdaptive(false)
        ChatAffordancePreferences(defaults: defaults).setHidesFastShare(true)
        ChatAffordancePreferences(defaults: defaults).setHidesGreetingSticker(true)
        AvatarCornerPreferences(defaults: defaults).setRadius(0)
        AvatarCornerPreferences(defaults: defaults).setUsesSingleRadius(true)
        let changed = defaults.persistentDomain(forName: name) ?? [:]
        XCTAssertEqual(changed.count - initial.count, 23)
        defaults.set("archive data", forKey: "gergram.archive.synthetic")
        defaults.set("native palette", forKey: "telegram.appearance.synthetic")

        resetGergramAppearance(defaults: defaults)

        let freshName = "Gergram.ResetTests.\(UUID().uuidString)"
        let fresh = try XCTUnwrap(UserDefaults(suiteName: freshName))
        defer { fresh.removePersistentDomain(forName: freshName) }
        resetGergramAppearance(defaults: fresh)
        let result = defaults.persistentDomain(forName: name) ?? [:]
        let clean = fresh.persistentDomain(forName: freshName) ?? [:]
        XCTAssertEqual(Set(clean.keys), Set(changed.keys))
        XCTAssertFalse(NSDictionary(dictionary: changed).isEqual(to: clean))
        for key in clean.keys {
            XCTAssertEqual(result[key] as? NSObject, clean[key] as? NSObject, key)
            XCTAssertNotEqual(changed[key] as? NSObject, clean[key] as? NSObject, key)
        }
        var editedStyle: ChatEditedIndicatorStyle?
        let subscription = ChatEditedIndicatorPreferences(defaults: defaults).signal.start(next: { editedStyle = $0 })
        subscription.dispose()
        XCTAssertEqual(editedStyle, .text)
        XCTAssertEqual(ChatMessageWidthPreferences(defaults: defaults).width, .standard)
        XCTAssertEqual(ChatMonospaceFontPreferences(defaults: defaults).font, .system)
        XCTAssertEqual(MessageBubbleRadiusPreferences(defaults: defaults).radius, MessageBubbleRadiusPreferences.defaultRadius)
        XCTAssertEqual(AvatarCornerPreferences(defaults: defaults).appearance, AvatarCornerAppearance())
        XCTAssertEqual(result["gergram.archive.synthetic"] as? String, "archive data")
        XCTAssertEqual(result["telegram.appearance.synthetic"] as? String, "native palette")
        resetGergramAppearance(defaults: defaults)
        XCTAssertTrue(NSDictionary(dictionary: result).isEqual(to: defaults.persistentDomain(forName: name) ?? [:]))
    }

    func testReactionResetEmitsOneChangeForAllKinds() {
        let name = "Gergram.ResetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = ChatReactionVisibilityPreferences(defaults: defaults)
        preferences.setHiddenKinds(Set(ChatReactionVisibilityPreferences.ChatKind.allCases))
        var eventSizes: [Int] = []
        let disposable = preferences.signal.start(next: { eventSizes.append($0.count) })
        preferences.setHiddenKinds([])
        preferences.setHiddenKinds([])
        disposable.dispose()
        XCTAssertEqual(eventSizes, [3, 0])
    }
}

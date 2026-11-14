import Foundation
import InAppSettings
import TGUIKit

func resetGergramAppearance(defaults: UserDefaults? = nil) {
    (defaults.map(ChatEditedIndicatorPreferences.init) ?? .shared).reset()
    (defaults.map(ProfileJoinDatePreferences.init) ?? .shared).setVisible(false)
    (defaults.map(ChatWallpaperVisibilityPreferences.init) ?? .shared).setHidden(false)
    (defaults.map(ComposerEmojiHoverPreferences.init) ?? .shared).setEnabled(true)
    (defaults.map(ComposerBotCommandsPreferences.init) ?? .shared).setHidden(false)
    (defaults.map(ComposerGiftButtonPreferences.init) ?? .shared).setHidden(false)
    (defaults.map(ComposerAIToolsButtonPreferences.init) ?? .shared).setHidden(false)
    (defaults.map(ComposerAutoDeleteButtonPreferences.init) ?? .shared).setHidden(false)
    (defaults.map(ComposerRichTextEditorPreferences.init) ?? .shared).setHidden(false)
    (defaults.map(StreamerModeMenuBarPreferences.init) ?? .shared).reset()
    (defaults.map(PremiumStatusVisibilityPreferences.init) ?? .shared).setHidden(false)
    (defaults.map(ChatReplyAppearancePreferences.init) ?? .shared).setSimplified(false)
    (defaults.map(ChatReactionVisibilityPreferences.init) ?? .shared).setHiddenKinds([])
    (defaults.map(MessageBubbleTailPreferences.init) ?? .shared).setHidden(false)
    (defaults.map(ChatMessageWidthPreferences.init) ?? .shared).set(.standard)
    (defaults.map(ChatMediaSpoilerPreferences.init) ?? .shared).setEnabled(false)
    (defaults.map(ChatMonospaceFontPreferences.init) ?? .shared).set(.system)
    (defaults.map(MessageBubbleRadiusPreferences.init) ?? .shared).setRadius(MessageBubbleRadiusPreferences.defaultRadius)
    (defaults.map(SwitchAnimationPreferences.init) ?? .shared).setEnabled(true)
    (defaults.map(ProfileMusicCoverPreferences.init) ?? .shared).setAdaptive(true)

    let affordances = defaults.map(ChatAffordancePreferences.init) ?? .shared
    affordances.setHidesFastShare(false)
    affordances.setHidesGreetingSticker(false)

    let avatars = defaults.map(AvatarCornerPreferences.init) ?? .shared
    avatars.setRadius(AvatarCornerPreferences.defaultRadius)
    avatars.setUsesSingleRadius(false)
}

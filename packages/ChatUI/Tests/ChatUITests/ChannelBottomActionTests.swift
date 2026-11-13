import Foundation
import InAppSettings
import Localization
import Postbox
import TelegramCore
import XCTest
@testable import ChatUI

final class ChannelBottomActionTests: XCTestCase {
    private let channelId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(100))
    private let discussionId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(101))

    override func setUp() {
        super.setUp()
        applyMacEnglishStrings()
        if !ChatInterfaceHooks.isInstalled {
            ChatInterfaceHooks.install(.init(
                freezeAlert: { _ in }, resolveUsername: { _, _ in .single(nil) },
                makeGroupCallPanelData: { _, _, _, _ in .complete() }, setChatInterfaceTempState: { _, _, _ in },
                inputSource: { _ in fatalError("Unexpected input source request") }, executeUrl: { _, _ in },
                executeConfirmedUrl: { _, _ in }, shareSwitchInlineQuery: { _, _, _ in },
                showLoginWidgetConfirmation: { _, _, _, _, _, _, _, _ in },
                makeNewPollController: { _, _ in fatalError("Unexpected poll request") },
                makeTopicIconFile: { _, _, _ in fatalError("Unexpected topic icon request") },
                peerIsForum: { _ in false }, urlPreviewInAppLink: { _, _ in .other }
            ))
        }
    }

    private func presentation(
        participation: TelegramChannelParticipationStatus = .member,
        flags: TelegramChannelFlags = [],
        isBroadcast: Bool = true,
        hasSuggestion: Bool = false
    ) -> ChatPresentationInterfaceState {
        let channel = TelegramChannel(
            id: channelId, accessHash: nil, title: "Channel", username: nil, photo: [], creationDate: 0, version: 0,
            participationStatus: participation,
            info: isBroadcast ? .broadcast(.init(flags: hasSuggestion ? [.hasMonoforum, .hasDiscussionGroup] : [.hasDiscussionGroup])) : .group(.init(flags: [])),
            flags: flags, restrictionInfo: nil, adminRights: nil, bannedRights: nil, defaultBannedRights: nil,
            usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil,
            profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil,
            verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: hasSuggestion ? discussionId : nil
        )
        return ChatPresentationInterfaceState(chatLocation: .peer(channelId), chatMode: .history)
            .updatedPeer { _ in channel }
            .updatedNotificationSettings(.defaultSettings)
    }

    private func title(of state: ChatState) -> String? {
        guard case let .action(title, _, _, _, _) = state else { return nil }
        return title
    }

    func testDiscussionFollowsLoadedLinkAndFallsBackToCurrentMuteAction() {
        let state = presentation()
        XCTAssertEqual(state.state(channelBottomAction: .native), state.state)
        XCTAssertEqual(title(of: state.state(channelBottomAction: .mute)), strings().chatInputMute)
        XCTAssertEqual(state.state(channelBottomAction: .discussion), state.state)

        let unlinked = state.withUpdatedDiscussionGroupId(.known(nil))
            .updatedNotificationSettings(TelegramPeerNotificationSettings.defaultSettings.withUpdatedMuteState(.muted(until: Int32.max)))
        XCTAssertEqual(title(of: unlinked.state(channelBottomAction: .discussion)), strings().chatInputUnmute)

        let linked = state.withUpdatedDiscussionGroupId(.known(discussionId))
        XCTAssertEqual(linked.state(channelBottomAction: .discussion), .channelBottomAction(.discussion(channelId: channelId, discussionId: discussionId), right: nil, left: nil))
        let newLink = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(102))
        XCTAssertNotEqual(linked.state(channelBottomAction: .discussion), linked.withUpdatedDiscussionGroupId(.known(newLink)).state(channelBottomAction: .discussion))
    }

    func testHiddenCollapsesOnlyWhenThereAreNoAdditionalActions() {
        let state = presentation()
        XCTAssertTrue(state.state(channelBottomAction: .hidden).isChannelBottomActionRowHidden)

        let withGift = state.withUpdatedCachedData(CachedChannelData().withUpdatedFlags([.starGiftsAvailable]))
        let withSuggestion = presentation(hasSuggestion: true)
        let cases: [(ChatPresentationInterfaceState, ChatState.AdditionIcon?, ChatState.AdditionIcon?)] = [
            (withGift, nil, .channel_gift),
            (withSuggestion, .monoforum_suggestion, nil)
        ]
        for (presentation, expectedLeft, expectedRight) in cases {
            let visible = presentation.state(channelBottomAction: .hidden)
            XCTAssertFalse(visible.isChannelBottomActionRowHidden)
            guard case let .channelBottomAction(.hidden, right, left) = visible else {
                return XCTFail("Expected hidden center action")
            }
            XCTAssertEqual(left?.icon, expectedLeft)
            XCTAssertEqual(right?.icon, expectedRight)
            XCTAssertNotEqual(visible, state.state(channelBottomAction: .hidden))
        }
    }

    func testActionsRespectJoinDeletePostingAndSelectionStates() {
        let joined = presentation()
        let left = presentation(participation: .left)
        let kicked = presentation(participation: .kicked)
        let owner = presentation(flags: [.isCreator])
        let group = presentation(isBroadcast: false)
        let inaccessible = joined.withUpdatedIsNotAccessible(true)
        let selecting = joined.withSelectionState()
        let changingChat = joined.withUpdatedChatLocation(.peer(discussionId))

        XCTAssertEqual(title(of: left.state), strings().chatInputJoin)
        XCTAssertEqual(title(of: kicked.state), strings().chatInputDelete)
        XCTAssertEqual(owner.state, .normal)
        XCTAssertEqual(selecting.state, .selecting)
        for mode in ChannelBottomAction.allCases {
            for state in [left, kicked, owner, group, inaccessible, selecting, changingChat] {
                XCTAssertEqual(state.state(channelBottomAction: mode), state.state)
            }
        }
    }

    func testPreferencePersistsAndSuppressesDuplicatesAfterFallback() throws {
        let suite = "Gergram.ChannelBottomAction.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(ChannelBottomActionPreferences(defaults: defaults).action, .native)

        defaults.set("unknownAction", forKey: "gergram.chat.channelBottomAction")
        let preferences = ChannelBottomActionPreferences(defaults: defaults)
        XCTAssertEqual(preferences.action, .native)

        var values: [ChannelBottomAction] = []
        let subscription = preferences.signal.start(next: { values.append($0) })
        preferences.setAction(.discussion)
        preferences.setAction(.discussion)
        XCTAssertEqual(ChannelBottomActionPreferences(defaults: defaults).action, .discussion)
        preferences.setAction(.mute)
        subscription.dispose()
        preferences.setAction(.hidden)
        XCTAssertEqual(values, [.native, .discussion, .mute])
    }
}

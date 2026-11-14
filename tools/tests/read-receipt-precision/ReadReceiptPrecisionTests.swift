import AppKit
import Foundation
import SwiftSignalKit
import XCTest

public typealias PeerId = Int
public struct Peer {
    let id: PeerId
    let compactDisplayTitle: String
}
enum Namespaces {
    enum Peer {
        static let CloudUser = 1
        static let CloudGroup = 2
    }
}
public struct Message {
    struct ID { let peerId: PeerKey }
    struct PeerKey { let namespace: Int }
    struct ReactionsAttribute { let reactions: [ReactionCount] }
    struct ReactionCount { let count: Int }
    let id: ID
    let anyMedia: Any? = nil
    let reactionsAttribute: ReactionsAttribute? = nil

    init(namespace: Int) {
        id = ID(peerId: PeerKey(namespace: namespace))
    }
}
public struct TelegramMediaFile {
    let isInstantVideo = false
    let isVoice = false
}
public enum EngineMessageReactionListContext {
    public struct State {
        let items: [Int]
        let totalCount: Int
    }
}
public protocol AccountContextProtocol { var timestamp: Int32 { get } }
struct AccountContext: AccountContextProtocol { let timestamp: Int32 }
enum FastSettings {
    private static let precision = ValuePromise(false, ignoreRepeated: true)
    static var showMessageTimestampSeconds = false {
        didSet { precision.set(showMessageTimestampSeconds) }
    }
    static var showMessageTimestampSecondsSignal: Signal<Bool, NoError> { precision.get() }
}

struct Strings {
    let chatMessageReadStatsEmptyViews = "No views"
    let chatMessageReadStatsShowDate = "Show read date"
    func chatContextReacted(_ reactions: String, _ read: String) -> String { "\(reactions) reactions / \(read) reads" }
    func chatContextReactedFastOther(_ count: Int) -> String { "\(count) reactions" }
    func chatMessageReadStatsWatchedOther(_ count: Int) -> String { "\(count) watched" }
    func chatMessageReadStatsListenedOther(_ count: Int) -> String { "\(count) listened" }
    func chatMessageReadStatsSeenOther(_ count: Int) -> String { "\(count) seen" }
    func timeTodayAt(_ time: String) -> String { "today at \(time)" }
}
func strings() -> Strings { Strings() }

extension String {
    func prefixWithDots(_ count: Int) -> String { String(prefix(count)) }
}

struct DateSelectorUtil {
    static let chatDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        formatter.timeZone = NSTimeZone.local
        return formatter
    }()
    static let chatFullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.timeZone = NSTimeZone.local
        return formatter
    }()
}

__SHORT_TIME__
__RELATIVE_TIME__

final class MenuRow {
    enum State {
        case loading
        case stats(read: [Peer]?, readTimestamps: [PeerId: Int32], reactions: EngineMessageReactionListContext.State?, customFiles: [TelegramMediaFile]?)

__PRIVATE_TEXT__
    }

    let item = NSMenuItem()
    fileprivate let message: Message
    fileprivate let context: AccountContext
    private let hiddenParticipants: Set<PeerId> = []
    fileprivate var state: State

__PRECISION_PROPERTIES__
__VISIBLE_TEXT__

    init(message: Message, context: AccountContext, state: State) {
        self.message = message
        self.context = context
        self.state = state
        self.item.title = visibleText
__PRECISION_SUBSCRIPTION__
    }

    deinit { timestampPrecisionDisposable?.dispose() }
}

struct ParticipantRow {
    let readTimestamp: Int32?
    let context: AccountContext

__PARTICIPANT_TEXT__
}

final class ReadReceiptPrecisionTests: XCTestCase {
    private let peer = Peer(id: 1, compactDisplayTitle: "Recipient")
    private let privateMessage = Message(namespace: Namespaces.Peer.CloudUser)
    private let reference: Int32 = 1_700_000_017

    override func tearDown() {
        FastSettings.showMessageTimestampSeconds = false
        super.tearDown()
    }

    func testPrivateReceiptTracksPreferenceOnSameDay() {
        let context = AccountContext(timestamp: reference)
        let state = readState()
        FastSettings.showMessageTimestampSeconds = false
        XCTAssertEqual(state.text(privateMessage, context: context), today(precision: .short))
        FastSettings.showMessageTimestampSeconds = true
        XCTAssertEqual(state.text(privateMessage, context: context), today(precision: .medium))
    }

    func testOlderPrivateReceiptUsesLocalizedFullDateAtBothPrecisions() {
        let timestamp = reference - 172_800
        let receipt = readState(timestamp: timestamp)
        let context = AccountContext(timestamp: reference)
        for (showsSeconds, precision) in [(false, DateFormatter.Style.short), (true, .medium)] {
            FastSettings.showMessageTimestampSeconds = showsSeconds
            XCTAssertEqual(receipt.text(privateMessage, context: context), format(timestamp, date: .medium, time: precision))
        }
    }

    func testMissingHiddenAndInvalidPrivateReceiptDatesStayUnavailable() {
        let context = AccountContext(timestamp: reference)
        FastSettings.showMessageTimestampSeconds = true
        for timestamp in [nil, 0, -1] as [Int32?] {
            XCTAssertEqual(readState(timestamp: timestamp).text(privateMessage, context: context), "Recipient")
        }
        let noReaders = MenuRow.State.stats(read: nil, readTimestamps: [:], reactions: nil, customFiles: nil)
        XCTAssertEqual(noReaders.text(privateMessage, context: context), "Show read date")
        XCTAssertEqual(readState().text(privateMessage, relativeTo: reference, excluding: [peer.id], showsTimestampSeconds: true), "1 seen")
    }

    func testGroupSummaryAndPrivateReactionCountsKeepTheirNativeText() {
        let context = AccountContext(timestamp: reference)
        FastSettings.showMessageTimestampSeconds = true
        let groupMessage = Message(namespace: Namespaces.Peer.CloudGroup)
        XCTAssertEqual(readState().text(groupMessage, context: context), "Recipient")
        let withReaction = MenuRow.State.stats(read: [peer], readTimestamps: [peer.id: reference], reactions: .init(items: [1], totalCount: 1), customFiles: nil)
        XCTAssertEqual(withReaction.text(privateMessage, context: context), "1 reactions")
    }

    func testParticipantReceiptFollowsPreferenceAndOmitsInvalidDates() {
        let context = AccountContext(timestamp: reference)
        let row = ParticipantRow(readTimestamp: reference, context: context)
        XCTAssertEqual(row.timestampText, today(precision: .short))
        FastSettings.showMessageTimestampSeconds = true
        XCTAssertEqual(row.timestampText, today(precision: .medium))
        XCTAssertNil(ParticipantRow(readTimestamp: nil, context: context).timestampText)
        XCTAssertNil(ParticipantRow(readTimestamp: 0, context: context).timestampText)
    }

    func testOpenPrivateRowUpdatesNativeTitleWhenPreferenceChanges() {
        let context = AccountContext(timestamp: reference)
        var row: MenuRow? = MenuRow(message: privateMessage, context: context, state: readState())
        let item = row!.item
        var titles: [String] = []
        let observation = item.observe(\.title, options: [.new]) { _, change in
            if let title = change.newValue { titles.append(title) }
        }
        XCTAssertEqual(item.title, today(precision: .short))
        FastSettings.showMessageTimestampSeconds = true
        XCTAssertEqual(item.title, today(precision: .medium))
        FastSettings.showMessageTimestampSeconds = true
        XCTAssertEqual(titles, [today(precision: .medium)])
        let retainedRow = { [weak row] in row }
        row = nil
        XCTAssertNil(retainedRow())
        FastSettings.showMessageTimestampSeconds = false
        XCTAssertEqual(titles, [today(precision: .medium)])
        observation.invalidate()
    }

    func testLegacyRelativeTimestampCallersRetainNativePrecision() {
        let timestamp = reference - 172_800
        for showsSeconds in [false, true] {
            FastSettings.showMessageTimestampSeconds = showsSeconds
            XCTAssertEqual(stringForRelativeTimestamp(relativeTimestamp: reference, relativeTo: reference), today(precision: .short))
            XCTAssertEqual(stringForRelativeTimestamp(relativeTimestamp: timestamp, relativeTo: reference), format(timestamp, date: .medium, time: .medium))
        }
    }

    private func readState(timestamp: Int32? = 1_700_000_017) -> MenuRow.State {
        .stats(read: [peer], readTimestamps: timestamp.map { [peer.id: $0] } ?? [:], reactions: nil, customFiles: nil)
    }

    private func today(precision: DateFormatter.Style) -> String {
        "today at \(format(reference, date: .none, time: precision))"
    }

    private func format(_ timestamp: Int32, date: DateFormatter.Style, time: DateFormatter.Style) -> String {
        DateFormatter.localizedString(from: Date(timeIntervalSince1970: Double(timestamp)), dateStyle: date, timeStyle: time)
    }
}

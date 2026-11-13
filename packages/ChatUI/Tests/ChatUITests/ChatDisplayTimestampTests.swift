import Foundation
import XCTest
@testable import ChatUI

final class ChatDisplayTimestampTests: XCTestCase {
    func testTimeStylesPreserveNativeMinutesAndExposeSeconds() {
        let date = Date(timeIntervalSince1970: 1_700_000_017)
        let minute = ChatDisplayTimestamp.time(for: date, showsSeconds: false)
        let second = ChatDisplayTimestamp.time(for: date, showsSeconds: true)
        XCTAssertEqual(minute, DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short))
        XCTAssertEqual(second, DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .medium))
        XCTAssertNotEqual(minute, second)
    }

    func testFullDateOmitsSecondsOnlyInMinuteMode() {
        let date = Date(timeIntervalSince1970: 1_700_000_017)
        let minute = ChatDisplayTimestamp.fullDate(for: date, showsSeconds: false)
        let second = ChatDisplayTimestamp.fullDate(for: date, showsSeconds: true)
        XCTAssertEqual(minute, DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short))
        XCTAssertEqual(second, DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .medium))
        XCTAssertNotEqual(minute, second)
    }

    func testServiceTimestampUsesAccountTimeCorrection() {
        let timestamp: Int32 = 1_700_000_017
        let corrected = Date(timeIntervalSince1970: TimeInterval(timestamp) - 60)
        XCTAssertEqual(
            ChatDisplayTimestamp.serviceTime(timestamp: timestamp, timeDifference: 60, showsSeconds: true,
                                             isRealMessage: true, hasText: true, isScheduledWhenOnline: false),
            ChatDisplayTimestamp.time(for: corrected, showsSeconds: true)
        )
    }

    func testServiceTimestampOmitsSyntheticTextlessAndScheduledRows() {
        let timestamp: Int32 = 1_700_000_017
        for (value, isRealMessage, hasText, isScheduledWhenOnline) in [
            (timestamp, false, true, false), (timestamp, true, false, false),
            (timestamp, true, true, true), (0, true, true, false)
        ] {
            XCTAssertNil(ChatDisplayTimestamp.serviceTime(timestamp: value, timeDifference: 0, showsSeconds: false,
                                                          isRealMessage: isRealMessage, hasText: hasText, isScheduledWhenOnline: isScheduledWhenOnline))
        }
    }
}

import Foundation
import XCTest
@testable import ChatUI

final class ChatMessageDetailsTests: XCTestCase {
    func testFormatsFullMessageIDAndTimestampSecondsInTheLocalTimeZone() {
        let details = ChatMessageDetails(id: Int32.max, sentAt: 1_700_000_001, editedAt: 1_700_000_009, forwardedAt: 1_700_000_000, views: 12_345, forwards: 7)
        let formatter = dateFormatter(secondsFromGMT: 7_200)

        XCTAssertEqual(details.value(for: .id, dateFormatter: formatter), "2147483647")
        XCTAssertEqual(details.value(for: .sent, dateFormatter: formatter), "2023-11-15 00:13:21")
        XCTAssertEqual(details.value(for: .edited, dateFormatter: formatter), "2023-11-15 00:13:29")
        XCTAssertEqual(details.value(for: .forwarded, dateFormatter: formatter), "2023-11-15 00:13:20")
        XCTAssertEqual(details.value(for: .views, dateFormatter: formatter), "12345")
        XCTAssertEqual(details.value(for: .forwards, dateFormatter: formatter), "7")
    }

    func testOmitsUnavailableDatesAndNonPositiveCounts() {
        let details = ChatMessageDetails(id: 15, sentAt: 0, editedAt: nil, forwardedAt: -1, views: 0, forwards: nil)
        let formatter = dateFormatter(secondsFromGMT: 0)

        XCTAssertEqual(details.value(for: .id, dateFormatter: formatter), "15")
        XCTAssertNil(details.value(for: .sent, dateFormatter: formatter))
        XCTAssertNil(details.value(for: .edited, dateFormatter: formatter))
        XCTAssertNil(details.value(for: .forwarded, dateFormatter: formatter))
        XCTAssertNil(details.value(for: .views, dateFormatter: formatter))
        XCTAssertNil(details.value(for: .forwards, dateFormatter: formatter))
    }

    private func dateFormatter(secondsFromGMT: Int) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: secondsFromGMT)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }
}

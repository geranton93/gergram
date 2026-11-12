import XCTest
@testable import PeerInfoUI

final class ProfileDataCenterTests: XCTestCase {
    func testUsesTheStatisticsSourceWhenBothAreKnown() {
        XCTAssertEqual(ProfileDataCenter(statistics: 4, profilePhoto: 2), .statistics(4))
        XCTAssertEqual(ProfileDataCenter(statistics: 4, profilePhoto: nil), .statistics(4))
    }

    func testUsesTheProfilePhotoSourceWhenStatisticsAreUnavailable() {
        XCTAssertEqual(ProfileDataCenter(statistics: nil, profilePhoto: 2), .profilePhoto(2))
        XCTAssertEqual(ProfileDataCenter(statistics: 0, profilePhoto: 2), .profilePhoto(2))
        XCTAssertEqual(ProfileDataCenter(statistics: -1, profilePhoto: 2), .profilePhoto(2))
    }

    func testOmitsAbsentAndInvalidDataCenters() {
        XCTAssertNil(ProfileDataCenter(statistics: nil, profilePhoto: nil))
        XCTAssertNil(ProfileDataCenter(statistics: 0, profilePhoto: -1))
    }
}

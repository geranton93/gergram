import XCTest
@testable import ChatUI

final class SocialPostPreviewTests: XCTestCase {
    func testSupportedPublicPostsPreferLargeMedia() {
        let posts = [
            "https://x.com/a_user/status/123456789",
            "HTTPS://MOBILE.TWITTER.COM:443/i/web/status/123456789",
            "https://www.tiktok.com/@a.user/video/123456789",
            "https://m.tiktok.com/@a_user/photo/123456789",
            "https://reddit.com/r/swift/comments/1abcd/",
            "https://www.reddit.com/r/swift/comments/1abcd/swift_news/?share=abc",
            "https://www.instagram.com/p/ABC_abc-123/",
            "https://instagram.com/reel/ABC_abc-123",
            "https://www.pixiv.net/artworks/123456",
            "https://www.pixiv.net/en/artworks/123456"
        ]
        for url in posts {
            XCTAssertTrue(SocialPostPreview.prefersLargeMedia(for: url), url)
        }
    }

    func testUnrecognizedPathsKeepNativeLayout() {
        let otherPages = [
            "https://x.com/a_user",
            "https://x.com/a_user/status/123/extra",
            "https://www.tiktok.com/@a.user",
            "https://vm.tiktok.com/share",
            "https://www.reddit.com/r/swift",
            "https://www.reddit.com/r/swift/comments/",
            "https://instagram.com/a_user",
            "https://www.pixiv.net/en/users/123456",
            "https://example.org/article"
        ]
        for url in otherPages {
            XCTAssertFalse(SocialPostPreview.prefersLargeMedia(for: url), url)
        }
    }

    func testOnlyExactHttpsOriginsAndCanonicalPathSegmentsMatch() {
        let invalidPosts = [
            "http://x.com/a_user/status/123",
            "//x.com/a_user/status/123",
            "https://x.com:8443/a_user/status/123",
            "https://x.com@evil.example/a_user/status/123",
            "https://evil.example@x.com/a_user/status/123",
            "https://x.com.evil.example/a_user/status/123",
            "https://%78.com/a_user/status/123",
            "https://ｘ.com/a_user/status/123",
            "https://fixupx.com/a_user/status/123",
            "https://x.com//a_user/status/123",
            "https://x.com/a_user/status/%31%32%33",
            "https://x.com/a_user/status/123%2F45",
            "https://x.com/a_user/status/123\n",
            "https://x.com/a_user/status/123?" + String(repeating: "x", count: 4096)
        ]
        for url in invalidPosts {
            XCTAssertFalse(SocialPostPreview.prefersLargeMedia(for: url), url)
        }
    }
}

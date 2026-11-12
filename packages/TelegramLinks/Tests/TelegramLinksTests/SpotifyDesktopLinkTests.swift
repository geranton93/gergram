import XCTest
@testable import TelegramLinks

final class SpotifyDesktopLinkTests: XCTestCase {
    func testRoutesSupportedResourcesAndRetainsHTTPSFallback() throws {
        let id = "6rqhFgbbKwnb9MLmUQDhG6"
        for type in ["track", "album", "artist", "playlist"] {
            let url = "https://open.spotify.com/\(type)/\(id)?si=shared&utm_source=copy-link"
            let link = try XCTUnwrap(SpotifyDesktopLink(url: url))
            XCTAssertEqual(link.appURL.absoluteString, "spotify:\(type):\(id)")
            XCTAssertEqual(link.webURL.absoluteString, url)
        }
    }

    func testRoutesUserProfilesAndLegacyUserPlaylists() {
        XCTAssertEqual(SpotifyDesktopLink(url: "https://OPEN.SPOTIFY.COM:443/user/a-user_1/")?.appURL.absoluteString, "spotify:user:a-user_1")
        XCTAssertEqual(SpotifyDesktopLink(url: "https://open.spotify.com/user/1185903410/playlist/6YAnJeVC7tgOiocOG23Dd")?.appURL.absoluteString,
                       "spotify:user:1185903410:playlist:6YAnJeVC7tgOiocOG23Dd")
    }

    func testRejectsLookalikesAndDeceptiveAuthorities() {
        let urls = [
            "https://open.spotify.com.example.com/track/id",
            "https://accounts.spotify.com/track/id",
            "https://open.spotify.com@evil.test/track/id",
            "https://user:password@open.spotify.com/track/id",
            "https://open%2espotify.com/track/id",
            "https://ＯＰＥＮ.spotify.com/track/id",
            "https://open.spotify.com./track/id",
            "https://open.spotify.com:8443/track/id",
            "http://open.spotify.com/track/id",
            "spotify:track:id",
        ]
        for url in urls {
            XCTAssertNil(SpotifyDesktopLink(url: url), url)
        }
    }

    func testLeavesUnsupportedOrAmbiguousURLsForTheWeb() {
        let urls = [
            "https://open.spotify.com/track/",
            "https://open.spotify.com/track/a%2Fb",
            "https://open.spotify.com/track/a%3Ab",
            "https://open.spotify.com/track/../id",
            "https://open.spotify.com//track/id",
            "https://open.spotify.com/track/id/more",
            "https://open.spotify.com/user/name/track/id",
            "https://open.spotify.com/episode/id",
            "https://open.spotify.com/track/id?target=https://evil.test",
            "https://open.spotify.com/track/id#context",
        ]
        for url in urls {
            XCTAssertNil(SpotifyDesktopLink(url: url), url)
        }
    }
}

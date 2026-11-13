import Foundation
import InAppSettings
import SwiftSignalKit
import XCTest

final class ChatWallpaperVisibilityPreferencesTests: XCTestCase {
    func testDefaultAndTogglePersistWithoutChangingOtherPreferences() throws {
        let name = "Gergram.ChatWallpaper.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("global wallpaper", forKey: "otherPreference")
        let preferences = ChatWallpaperVisibilityPreferences(defaults: defaults)
        var values: [Bool] = []
        let disposable = preferences.signal.start(next: { values.append($0) })

        preferences.setHidden(true)
        preferences.setHidden(true)
        let reloaded = ChatWallpaperVisibilityPreferences(defaults: defaults)
        var persisted: [Bool] = []
        let secondDisposable = reloaded.signal.start(next: { persisted.append($0) })
        secondDisposable.dispose()
        preferences.setHidden(false)
        disposable.dispose()
        preferences.setHidden(true)

        XCTAssertEqual(values, [false, true, false])
        XCTAssertEqual(persisted, [true])
        XCTAssertEqual(defaults.string(forKey: "otherPreference"), "global wallpaper")
    }
}

import Postbox
import TelegramCore
import XCTest
@testable import EntertainmentUI

final class PanelStickerSearchVisibilityTests: XCTestCase {
    private struct TestItem: ItemCollectionItem {
        let index: ItemCollectionItemIndex
        let indexKeys: [MemoryBuffer] = []

        init(_ id: Int64) {
            index = ItemCollectionItemIndex(index: 0, id: id)
        }

        init(decoder: PostboxDecoder) {
            self.init(decoder.decodeInt64ForKey("id", orElse: 0))
        }

        func encode(_ encoder: PostboxEncoder) {
            encoder.encodeInt64(index.id, forKey: "id")
        }
    }

    private let added = ItemCollectionId(namespace: 1, id: 10)
    private let unadded = ItemCollectionId(namespace: 1, id: 20)

    private func info(_ id: ItemCollectionId) -> StickerPackCollectionInfo {
        StickerPackCollectionInfo(
            id: id, flags: .init(), accessHash: 0, title: "Test", shortName: "test",
            thumbnail: nil, thumbnailFileId: nil, immediateThumbnailData: nil, hash: 0, count: 1
        )
    }

    private func entry(_ pack: ItemCollectionId, itemId: Int64) -> ItemCollectionViewEntry {
        let item = TestItem(itemId)
        return ItemCollectionViewEntry(
            index: ItemCollectionViewEntryIndex(collectionIndex: 0, collectionId: pack, itemIndex: item.index),
            item: item
        )
    }

    private func source() -> FoundStickerSets {
        FoundStickerSets(
            infos: [(unadded, info(unadded), nil, true), (added, info(added), nil, false), (added, info(added), nil, true)],
            entries: [entry(unadded, itemId: 101), entry(added, itemId: 203), entry(added, itemId: 203)]
        )
    }

    func testDisabledPreferencePreservesAllResultsBeforeInstalledLookup() {
        let result = panelStickerSearchPacks(source(), showsOnlyAddedPacks: false, installedIds: nil)
        XCTAssertEqual(result.infos.map { $0.0 }, [unadded, added, added])
        XCTAssertEqual(result.entries.map { $0.index.collectionId }, [unadded, added, added])
        XCTAssertFalse(result.infos[1].3)
    }

    func testEnabledPreferenceOmitsPacksBeforeInstalledLookup() {
        let result = panelStickerSearchPacks(source(), showsOnlyAddedPacks: true, installedIds: nil)
        XCTAssertTrue(result.infos.isEmpty)
        XCTAssertTrue(result.entries.isEmpty)
    }

    func testInstalledSnapshotWinsOverStaleResultFlagsAndDeduplicatesEntries() {
        let result = panelStickerSearchPacks(source(), showsOnlyAddedPacks: true, installedIds: [added])
        XCTAssertEqual(result.infos.map { $0.0 }, [added])
        XCTAssertEqual(result.infos.map { $0.3 }, [true])
        XCTAssertEqual(result.entries.map { $0.index.collectionId }, [added])
        XCTAssertEqual(result.entries.map { $0.index.itemIndex.id }, [203])
    }

    func testRemovingAnInstalledPackFromTheSnapshotHidesIt() {
        let packs = source()
        XCTAssertFalse(panelStickerSearchPacks(packs, showsOnlyAddedPacks: true, installedIds: [added]).infos.isEmpty)
        let result = panelStickerSearchPacks(packs, showsOnlyAddedPacks: true, installedIds: [])
        XCTAssertTrue(result.infos.isEmpty)
        XCTAssertTrue(result.entries.isEmpty)
    }
}

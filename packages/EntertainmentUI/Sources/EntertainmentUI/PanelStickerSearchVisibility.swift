import Postbox
import TelegramCore

func panelStickerSearchPacks(
    _ packs: FoundStickerSets, showsOnlyAddedPacks: Bool, installedIds: Set<ItemCollectionId>?
) -> FoundStickerSets {
    guard showsOnlyAddedPacks else { return packs }
    guard let installedIds else { return FoundStickerSets() }

    var seenPacks = Set<ItemCollectionId>()
    let infos = packs.infos.compactMap { info -> (ItemCollectionId, ItemCollectionInfo, ItemCollectionItem?, Bool)? in
        guard installedIds.contains(info.0), seenPacks.insert(info.0).inserted else { return nil }
        return (info.0, info.1, info.2, true)
    }
    var seenItems: [ItemCollectionId: Set<ItemCollectionItemIndex.Id>] = [:]
    let entries = packs.entries.filter { entry in
        let id = entry.index.collectionId
        return seenPacks.contains(id) && seenItems[id, default: []].insert(entry.index.itemIndex.id).inserted
    }
    return FoundStickerSets(infos: infos, entries: entries)
}

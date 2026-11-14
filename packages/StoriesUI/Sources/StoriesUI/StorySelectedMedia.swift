import TelegramCore

func selectedStoryMedia(_ story: EngineStoryItem, preferHighQuality: Bool) -> EngineMedia {
    if preferHighQuality {
        return story.media
    }
    return story.alternativeMediaList.first ?? story.media
}

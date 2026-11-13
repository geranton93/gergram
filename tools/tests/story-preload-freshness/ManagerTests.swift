final class StoryPreloadManagerTests: XCTestCase {
    func info(_ id: Int32 = 1, revision: Int = 0) -> StoryPreloadInfo {
        .init(peer: PeerReference(.init(id: 10))!,storyId: id,media: .init(id: .init(id: Int(id)),revision: revision),reactions: [],priority: .top(position: Int(id)))
    }
    func testNearestPriorityTransitionRebindsOnlyTheAffectedAttempt() {
        let context = Context()
        let manager = StoryMediaPreloadContext()
        let first = info()
        let second = info(2)
        manager.update([first, second]) { preloadStoryMedia(context: context, info: $0) }
        let nearest = StoryPreloadInfo(peer: first.peer, storyId: first.storyId, media: first.media, reactions: first.reactions, priority: .top(position: 0))
        manager.update([nearest, second]) { preloadStoryMedia(context: context, info: $0) }
        XCTAssertEqual(context.attempts.map { $0.info.storyId }, [first.storyId, second.storyId, first.storyId])
        XCTAssertTrue(context.attempts[0].disposed)
        XCTAssertFalse(context.attempts[1].disposed)
        XCTAssertFalse(context.attempts[2].disposed)
        manager.dispose()
    }

    func testSynchronousReentryDoesNotOverwriteNewAttempt() {
        let manager=StoryMediaPreloadContext(); let c=Context(); var reentered=false
        c.onStart={ _ in if !reentered { reentered=true; manager.update([self.info(revision: 2)]) { preloadStoryMedia(context: c,info: $0) } } }
        manager.update([info()]) { preloadStoryMedia(context: c,info: $0) }
        XCTAssertEqual(c.attempts.count,2); XCTAssertTrue(c.attempts[0].disposed); XCTAssertFalse(c.attempts[1].disposed); manager.dispose(); c.onStart=nil
    }
    func testFactoryReentryWithUnchangedInfoStillStartsRequest() {
        let manager=StoryMediaPreloadContext(); let c=Context(); let value=info()
        manager.update([value]) { info in
            manager.update([value]) { preloadStoryMedia(context: c,info: $0) }
            return preloadStoryMedia(context: c,info: info)
        }
        XCTAssertEqual(c.attempts.count,1); manager.dispose()
    }
    func testDisposalDuringFactoryPreventsSubscription() {
        let manager=StoryMediaPreloadContext(); let c=Context()
        manager.update([info()]) { info in manager.dispose(); return preloadStoryMedia(context: c,info: info) }
        XCTAssertTrue(c.attempts.isEmpty)
    }
    func testSynchronousOwnerDisposalCancelsReturnedSubscription() {
        let manager=StoryMediaPreloadContext(); let c=Context(); c.onStart={ _ in manager.dispose() }
        manager.update([info(),info(2)]) { preloadStoryMedia(context: c,info: $0) }
        XCTAssertEqual(c.attempts.count,1); XCTAssertTrue(c.attempts[0].disposed); c.onStart=nil
    }
    func testDisposedManagerDoesNotRestart() {
        let manager=StoryMediaPreloadContext(); let c=Context(); manager.dispose()
        manager.update([info()]) { preloadStoryMedia(context: c,info: $0) }; XCTAssertTrue(c.attempts.isEmpty)
    }
    func testReentryDuringRemovalWinsOverOldUpdate() {
        let manager=StoryMediaPreloadContext(); let c=Context(); manager.update([info()]) { preloadStoryMedia(context: c,info: $0) }
        var reentered=false; c.onDispose={ _ in if !reentered { reentered=true; manager.update([self.info(3)]) { preloadStoryMedia(context: c,info: $0) } } }
        manager.update([info(2)]) { preloadStoryMedia(context: c,info: $0) }
        XCTAssertEqual(c.attempts.map { $0.info.storyId },[1,3]); c.onDispose=nil; manager.dispose()
    }
}

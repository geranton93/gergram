import Foundation
import SwiftSignalKit
import XCTest

private enum Namespaces {
    enum Peer { static let SecretChat = 3 }
    enum Message { static let Cloud = 0 }
}

private struct PeerId: Equatable {
    let id: Int64
    var namespace = 0
}

private struct MessageId {
    let peerId: PeerId
    var namespace = Namespaces.Message.Cloud
    var id: Int32 = 30
}

private struct MessageReference {
    let id: MessageId?
    var isIncoming: Bool? = false
    var isSecret: Bool? = false
}

private enum PartialMediaReference {
    case message(message: MessageReference)
    case webPage
}

private struct TelegramMediaImage {
    enum Reference { case cloud(Int64, Int64, Data?) }
    var reference: Reference?
    var partialReference: PartialMediaReference?

    func withUpdatedPartialReference(_ reference: PartialMediaReference?) -> Self {
        var image = self
        image.partialReference = reference
        return image
    }
}

private struct CloudPhotoSizeMediaResource {
    var photoId: Int64 = 42
    var accessHash: Int64 = 77
    var sizeSpec = "x"
    var fileReference: Data? = Data([2])
}

private struct ImageRepresentation { let resource: Any }
private struct MediaResourceReference {
    let message: MessageReference?
    let photo: TelegramMediaImage?
}
private enum AnyMediaReference {
    case message(message: MessageReference, media: TelegramMediaImage)
    case standalone

    var partial: PartialMediaReference? {
        if case let .message(message, _) = self { return .message(message: message) }
        return nil
    }

    func resourceReference(_ resource: CloudPhotoSizeMediaResource) -> MediaResourceReference {
        if case let .message(message, media) = self { return MediaResourceReference(message: message, photo: media) }
        return MediaResourceReference(message: nil, photo: nil)
    }
}

private struct TelegramCloudMediaResourceFetchInfo {
    let reference: MediaResourceReference
    let preferBackgroundReferenceRevalidation: Bool
    let continueInBackground: Bool
}
private enum RevalidateMediaReferenceError { case generic }
private enum PendingMessageUploadError: Error { case generic }
private struct RevalidatedMediaResource { let updatedResource: Any }

private final class MediaReferenceRevalidationContext {
    var calls: [TelegramCloudMediaResourceFetchInfo] = []
    var reply: Signal<RevalidatedMediaResource, RevalidateMediaReferenceError> = .single(.init(updatedResource: CloudPhotoSizeMediaResource()))
}

private func revalidateMediaResourceReference(accountPeerId: PeerId, postbox: Void, network: Void, revalidationContext: MediaReferenceRevalidationContext, info: TelegramCloudMediaResourceFetchInfo, resource: CloudPhotoSizeMediaResource) -> Signal<RevalidatedMediaResource, RevalidateMediaReferenceError> {
    revalidationContext.calls.append(info)
    return revalidationContext.reply
}

private struct Buffer { let data: Data }
private enum Api {
    enum InputPhoto {
        struct Value {
            let id: Int64
            let accessHash: Int64
            let fileReference: Buffer
        }
        case inputPhoto(Value)
    }
    enum InputMedia {
        struct Value {
            let flags: Int
            let id: InputPhoto
            let ttlSeconds: Int?
            let video: Int?
        }
        case inputMediaPhoto(Value)
    }
}
private enum PendingMessageUploadedContent {
    case media(Api.InputMedia, String)
}
private struct PendingMessageUploadedContentAndReuploadInfo {
    let content: PendingMessageUploadedContent
    let reuploadInfo: Int?
    let cacheReferenceKey: Int?
}
private enum PendingMessageUploadedContentResult {
    case content(PendingMessageUploadedContentAndReuploadInfo)
}

private let destination = PeerId(id: 9)
private let sourceMessage = MessageReference(id: MessageId(peerId: destination))
private let originalFileReference = Data([1])
private let refreshedFileReference = Data([2])

private func photoContent(peerId: PeerId = destination, source: PartialMediaReference? = .message(message: sourceMessage), explicit: AnyMediaReference? = nil, largest: ImageRepresentation = ImageRepresentation(resource: CloudPhotoSizeMediaResource()), forceReupload: Bool, isGrouped: Bool = false, revalidationContext: MediaReferenceRevalidationContext) -> Signal<PendingMessageUploadedContentResult, PendingMessageUploadError> {
    let image = TelegramMediaImage(reference: .cloud(42, 77, originalFileReference), partialReference: nil)
    let accountPeerId = PeerId(id: 1)
    let postbox: Void = ()
    let network: Void = ()
    let mediaReference = explicit
    let explicitPartialReference = source
    let text = "Original caption"
    __PHOTO_BRANCH__
}

final class RepeatPhotoReferenceTests: XCTestCase {
    func testInitialAttemptKeepsOriginalReferenceWithoutRevalidation() {
        let revalidator = MediaReferenceRevalidationContext()
        assertPhoto(photoContent(forceReupload: false, revalidationContext: revalidator), reference: originalFileReference)
        XCTAssertTrue(revalidator.calls.isEmpty)
    }

    func testRetryUsesFreshExactSourceReferenceAndKeepsCaption() throws {
        let revalidator = MediaReferenceRevalidationContext()
        assertPhoto(photoContent(forceReupload: true, revalidationContext: revalidator), reference: refreshedFileReference)
        let call = try XCTUnwrap(revalidator.calls.first)
        XCTAssertEqual(revalidator.calls.count, 1)
        XCTAssertEqual(call.reference.message?.id?.id, sourceMessage.id?.id)
        XCTAssertEqual(call.reference.message?.id?.peerId, destination)
        guard case let .message(message)? = call.reference.photo?.partialReference else { return XCTFail("Missing exact photo origin") }
        XCTAssertEqual(message.id?.id, sourceMessage.id?.id)
        XCTAssertFalse(call.preferBackgroundReferenceRevalidation)
        XCTAssertFalse(call.continueInBackground)
    }

    func testExplicitSourceOverridesStaleImageAndStoredReference() throws {
        let revalidator = MediaReferenceRevalidationContext()
        let explicit = AnyMediaReference.message(message: sourceMessage, media: .init(reference: nil, partialReference: .webPage))
        assertPhoto(photoContent(source: .webPage, explicit: explicit, forceReupload: true, revalidationContext: revalidator), reference: refreshedFileReference)
        let call = try XCTUnwrap(revalidator.calls.first)
        guard case .message? = call.reference.photo?.partialReference else { return XCTFail("Wrong reference used for revalidation") }
    }

    func testUnrelatedReferencePathsKeepNativeBehavior() {
        let revalidator = MediaReferenceRevalidationContext()
        let unrelated: [PartialMediaReference?] = [
            nil,
            .webPage,
            .message(message: .init(id: nil)),
            .message(message: .init(id: .init(peerId: PeerId(id: 25)))),
            .message(message: .init(id: .init(peerId: destination, namespace: 1))),
            .message(message: .init(id: .init(peerId: destination, id: 0))),
            .message(message: .init(id: .init(peerId: destination), isIncoming: true)),
            .message(message: .init(id: .init(peerId: destination), isSecret: true)),
        ]
        for reference in unrelated {
            assertPhoto(photoContent(source: reference, forceReupload: true, revalidationContext: revalidator), reference: originalFileReference)
        }
        assertPhoto(photoContent(forceReupload: true, isGrouped: true, revalidationContext: revalidator), reference: originalFileReference)
        assertPhoto(photoContent(largest: ImageRepresentation(resource: "local path"), forceReupload: true, revalidationContext: revalidator), reference: originalFileReference)
        XCTAssertTrue(revalidator.calls.isEmpty)
    }

    func testInvalidRefreshCannotSend() {
        let revalidator = MediaReferenceRevalidationContext()
        let invalid: [Any] = [
            CloudPhotoSizeMediaResource(photoId: 12),
            CloudPhotoSizeMediaResource(accessHash: 12),
            CloudPhotoSizeMediaResource(sizeSpec: "m"),
            CloudPhotoSizeMediaResource(fileReference: nil),
            CloudPhotoSizeMediaResource(fileReference: Data()),
            CloudPhotoSizeMediaResource(fileReference: originalFileReference),
            "invalid",
        ]
        for result in invalid {
            revalidator.reply = .single(.init(updatedResource: result))
            assertError(photoContent(forceReupload: true, revalidationContext: revalidator))
        }
        revalidator.reply = .fail(.generic)
        assertError(photoContent(forceReupload: true, revalidationContext: revalidator))
    }

    func testCancelsNativeRevalidationWhenSendIsDisposed() {
        let revalidator = MediaReferenceRevalidationContext()
        let disposed = expectation(description: "native revalidation disposed")
        revalidator.reply = Signal { _ in
            ActionDisposable { disposed.fulfill() }
        }
        let request = photoContent(forceReupload: true, revalidationContext: revalidator).start(
            next: { _ in XCTFail("Cancelled request produced media") },
            error: { _ in XCTFail("Cancelled request produced error") }
        )
        request.dispose()
        wait(for: [disposed], timeout: 1)
    }

    func testMissingOriginTimesOutAndCancelsNativeRequest() {
        let revalidator = MediaReferenceRevalidationContext()
        let disposed = expectation(description: "timed out revalidation disposed")
        revalidator.reply = Signal { _ in
            ActionDisposable { disposed.fulfill() }
        }
        assertError(photoContent(forceReupload: true, revalidationContext: revalidator), timeout: 17)
        wait(for: [disposed], timeout: 1)
    }

    private func assertPhoto(_ result: Signal<PendingMessageUploadedContentResult, PendingMessageUploadError>, reference: Data, file: StaticString = #filePath, line: UInt = #line) {
        let sent = expectation(description: "cloud photo ready")
        let disposable = result.start(next: { result in
            guard case let .content(value) = result,
                  case let .media(.inputMediaPhoto(input), text) = value.content,
                  case let .inputPhoto(photo) = input.id else {
                XCTFail("Expected cloud photo with caption", file: file, line: line)
                return
            }
            XCTAssertEqual(photo.fileReference.data, reference, file: file, line: line)
            XCTAssertEqual(photo.id, 42, file: file, line: line)
            XCTAssertEqual(photo.accessHash, 77, file: file, line: line)
            XCTAssertEqual(text, "Original caption", file: file, line: line)
            XCTAssertEqual(input.flags, 0, file: file, line: line)
            XCTAssertNil(input.ttlSeconds, file: file, line: line)
            XCTAssertNil(input.video, file: file, line: line)
            sent.fulfill()
        }, error: { _ in XCTFail("Unexpected upload error", file: file, line: line) })
        wait(for: [sent], timeout: 1)
        disposable.dispose()
    }

    private func assertError(_ result: Signal<PendingMessageUploadedContentResult, PendingMessageUploadError>, timeout: TimeInterval = 1, file: StaticString = #filePath, line: UInt = #line) {
        let failed = expectation(description: "cloud photo failed")
        let disposable = result.start(next: { _ in
            XCTFail("Unexpected outgoing photo", file: file, line: line)
        }, error: { _ in
            failed.fulfill()
        })
        wait(for: [failed], timeout: timeout)
        disposable.dispose()
    }
}

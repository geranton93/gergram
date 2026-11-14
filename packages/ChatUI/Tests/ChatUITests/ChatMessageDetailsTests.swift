import Foundation
import Postbox
import TelegramCore
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

    func testFormatsDirectDocumentMetadataAndKeepsFullFileNameForCopy() throws {
        let name = String(repeating: "📄", count: 45) + ".png"
        let resource = CloudDocumentMediaResource(datacenterId: 5, fileId: 1, accessHash: 0, size: 1_024, fileReference: nil, fileName: nil)
        let file = TelegramMediaFile(
            fileId: MediaId(namespace: Namespaces.Media.CloudFile, id: 1),
            partialReference: nil,
            resource: resource,
            previewRepresentations: [],
            videoThumbnails: [],
            immediateThumbnailData: nil,
            mimeType: "image/png",
            size: 0,
            attributes: [.FileName(fileName: name), .ImageSize(size: PixelDimensions(width: 640, height: 480))],
            alternativeRepresentations: []
        )
        let details = try XCTUnwrap(ChatMessageDetailsAction.attachmentDetails(for: [file], isConcealed: false).first?.details)

        XCTAssertEqual(details.value(for: .fileSize), ByteCountFormatter.string(fromByteCount: 1_024, countStyle: .file))
        XCTAssertEqual(details.value(for: .mimeType), "image/png")
        XCTAssertEqual(details.value(for: .fileName), name)
        XCTAssertEqual(ChatMessageDetails.Field.fileName.menuValue(name), "…" + String(name.suffix(40)))
        XCTAssertEqual(details.value(for: .resolution), "640 × 480")
        XCTAssertEqual(details.value(for: .mediaDataCenter), "5")
        XCTAssertTrue(ChatMessageDetailsAction.attachmentDetails(for: [file], isConcealed: true).isEmpty)
    }

    func testUsesOneLargestEligiblePhotoOrVideoRepresentationForAllFields() throws {
        let small = photoResource(size: 400, dataCenter: 2, spec: "s")
        let large = photoResource(size: 9_000, dataCenter: 4, spec: "x")
        let local = LocalFileReferenceMediaResource(localFilePath: "/tmp/message-details-test", randomId: 1, size: 12_000)
        let photoRepresentations = [
            photoRepresentation(small, width: 100, height: 80),
            photoRepresentation(large, width: 800, height: 600),
            photoRepresentation(local, width: 1_600, height: 1_200)
        ]
        let photo = image(representations: photoRepresentations)
        let photoDetails = try XCTUnwrap(ChatMessageDetailsAction.attachmentDetails(for: [photo], isConcealed: false).first?.details)
        XCTAssertEqual(photoDetails.fileSize, 9_000)
        XCTAssertEqual(photoDetails.mimeType, "image/jpeg")
        XCTAssertEqual(photoDetails.dataCenter, 4)
        XCTAssertEqual(photoDetails.dimensions?.width, 800)
        XCTAssertEqual(photoDetails.dimensions?.height, 600)
        XCTAssertNil(photoDetails.fileName)

        let videos = [
            TelegramMediaImage.VideoRepresentation(dimensions: PixelDimensions(width: 200, height: 160), resource: small, startTimestamp: nil),
            TelegramMediaImage.VideoRepresentation(dimensions: PixelDimensions(width: 400, height: 300), resource: large, startTimestamp: nil),
            TelegramMediaImage.VideoRepresentation(dimensions: PixelDimensions(width: -1, height: 2_000), resource: large, startTimestamp: nil)
        ]
        let moving = image(representations: photoRepresentations, videos: videos)
        let videoDetails = try XCTUnwrap(ChatMessageDetailsAction.attachmentDetails(for: [moving], isConcealed: false).first?.details)
        XCTAssertEqual(videoDetails.fileSize, 9_000)
        XCTAssertEqual(videoDetails.mimeType, "video/mp4")
        XCTAssertEqual(videoDetails.dataCenter, 4)
        XCTAssertEqual(videoDetails.dimensions?.width, 400)
        XCTAssertEqual(videoDetails.dimensions?.height, 300)

        let originalVideo = file(id: 3, resourceId: 19, name: "original.mp4", mimeType: "video/mp4")
        let withOriginal = image(representations: photoRepresentations, videos: videos, video: originalVideo)
        let details = try XCTUnwrap(ChatMessageDetailsAction.attachmentDetails(for: [withOriginal], isConcealed: false).first)
        XCTAssertEqual(details.selection.resourceId, originalVideo.resource.id)
        XCTAssertEqual(details.details.value(for: .fileName), "original.mp4")
    }

    func testOmitsUnknownUnsafeOrNonCloudMetadata() {
        let metadata = ChatMessageDetails.MediaDetails(
            fileSize: -1, mimeType: "  ", fileName: "file\u{202E}.png", dimensions: (0, 400), dataCenter: 0
        )
        for field in [ChatMessageDetails.Field.fileSize, .mimeType, .fileName, .resolution, .mediaDataCenter] {
            XCTAssertNil(metadata.value(for: field))
        }
        let local = LocalFileReferenceMediaResource(localFilePath: "/tmp/message-details-test", randomId: 1, size: 12_000)
        let localImage = image(representations: [photoRepresentation(local, width: 800, height: 600)])
        XCTAssertTrue(ChatMessageDetailsAction.attachmentDetails(for: [localImage], isConcealed: false).isEmpty)
        XCTAssertTrue(ChatMessageDetailsAction.attachmentDetails(for: [], isConcealed: false).isEmpty)
    }

    func testKeepsDistinctDirectAttachmentsInOrderAndUsesTheSelectedIdentityAfterReordering() throws {
        let first = file(id: 1, resourceId: 51, name: "first.pdf")
        let second = file(id: 2, resourceId: 52, name: "[second](https://invalid.test).pdf")
        let local = LocalFileReferenceMediaResource(localFilePath: "/tmp/message-details-test", randomId: 1, size: 12_000)
        let localImage = image(representations: [photoRepresentation(local, width: 800, height: 600)])
        let rows = ChatMessageDetailsAction.attachmentDetails(for: [first, localImage, second], isConcealed: false)
        XCTAssertEqual(rows.map(\.selection.id), [.file(first.fileId), .file(second.fileId)])
        XCTAssertEqual(rows.map(\.selection.resourceId), [first.resource.id, second.resource.id])
        let selected = try XCTUnwrap(rows.last?.selection)
        let copied = ChatMessageDetailsAction.attachmentValue(for: .fileName, selection: selected, in: [second, first], isConcealed: false)
        XCTAssertEqual(copied, "[second](https://invalid.test).pdf")
    }

    func testRefusesClipboardValueWhenSelectionDisappearsChangesResourceOrBecomesConcealed() throws {
        let file = self.file(id: 1, resourceId: 51, name: "first.pdf")
        let replacement = self.file(id: 1, resourceId: 52, name: "replacement.pdf")
        let fileReferenceRefresh = self.file(id: 1, resourceId: 51, name: "first.pdf", fileReference: Data([1]))
        let selected = try XCTUnwrap(ChatMessageDetailsAction.attachmentDetails(for: [file], isConcealed: false).first?.selection)
        XCTAssertNil(ChatMessageDetailsAction.attachmentValue(for: .fileName, selection: selected, in: [], isConcealed: false))
        XCTAssertNil(ChatMessageDetailsAction.attachmentValue(for: .fileName, selection: selected, in: [replacement], isConcealed: false))
        XCTAssertNil(ChatMessageDetailsAction.attachmentValue(for: .fileName, selection: selected, in: [file, replacement], isConcealed: false))
        XCTAssertNil(ChatMessageDetailsAction.attachmentValue(for: .fileName, selection: selected, in: [file], isConcealed: true))
        XCTAssertEqual(ChatMessageDetailsAction.attachmentValue(for: .fileName, selection: selected, in: [fileReferenceRefresh], isConcealed: false), "first.pdf")
    }

    private func file(id: Int64, resourceId: Int64, name: String, mimeType: String = "application/pdf", fileReference: Data? = nil) -> TelegramMediaFile {
        let resource = CloudDocumentMediaResource(datacenterId: 5, fileId: resourceId, accessHash: 0, size: 1_024, fileReference: fileReference, fileName: nil)
        return TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.CloudFile, id: id), partialReference: nil,
                                 resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil,
                                 mimeType: mimeType, size: 1_024, attributes: [.FileName(fileName: name)], alternativeRepresentations: [])
    }

    private func photoResource(size: Int64, dataCenter: Int32, spec: String) -> CloudPhotoSizeMediaResource {
        CloudPhotoSizeMediaResource(datacenterId: dataCenter, photoId: 1, accessHash: 0, sizeSpec: spec, size: size, fileReference: nil)
    }

    private func photoRepresentation(_ resource: TelegramMediaResource, width: Int32, height: Int32) -> TelegramMediaImageRepresentation {
        TelegramMediaImageRepresentation(
            dimensions: PixelDimensions(width: width, height: height),
            resource: resource,
            progressiveSizes: [],
            immediateThumbnailData: nil,
            hasVideo: false,
            isPersonal: false
        )
    }

    private func image(representations: [TelegramMediaImageRepresentation], videos: [TelegramMediaImage.VideoRepresentation] = [], video: TelegramMediaFile? = nil) -> TelegramMediaImage {
        TelegramMediaImage(
            imageId: MediaId(namespace: Namespaces.Media.CloudImage, id: 1),
            representations: representations,
            videoRepresentations: videos,
            immediateThumbnailData: nil,
            reference: nil,
            partialReference: nil,
            flags: [],
            video: video
        )
    }

    private func dateFormatter(secondsFromGMT: Int) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: secondsFromGMT)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }
}

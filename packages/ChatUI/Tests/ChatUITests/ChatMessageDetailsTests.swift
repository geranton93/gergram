import Foundation
import Postbox
import TelegramCore
import XCTest
@testable import ChatUI

final class ChatMessageDetailsTests: XCTestCase {
    func testFormatsFullMessageIDAndTimestampSecondsInTheLocalTimeZone() {
        let details = ChatMessageDetails(id: Int32.max, sentAt: 1_700_000_001, editedAt: 1_700_000_009, forwardedAt: 1_700_000_000, views: 12_345, forwards: 7, media: nil)
        let formatter = dateFormatter(secondsFromGMT: 7_200)

        XCTAssertEqual(details.value(for: .id, dateFormatter: formatter), "2147483647")
        XCTAssertEqual(details.value(for: .sent, dateFormatter: formatter), "2023-11-15 00:13:21")
        XCTAssertEqual(details.value(for: .edited, dateFormatter: formatter), "2023-11-15 00:13:29")
        XCTAssertEqual(details.value(for: .forwarded, dateFormatter: formatter), "2023-11-15 00:13:20")
        XCTAssertEqual(details.value(for: .views, dateFormatter: formatter), "12345")
        XCTAssertEqual(details.value(for: .forwards, dateFormatter: formatter), "7")
    }

    func testOmitsUnavailableDatesAndNonPositiveCounts() {
        let details = ChatMessageDetails(id: 15, sentAt: 0, editedAt: nil, forwardedAt: -1, views: 0, forwards: nil, media: nil)
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
        let media = try XCTUnwrap(ChatMessageDetailsAction.mediaDetails(for: [file], isConcealed: false))
        let details = ChatMessageDetails(id: 1, sentAt: 0, editedAt: nil, forwardedAt: nil, views: nil, forwards: nil, media: media)
        let formatter = dateFormatter(secondsFromGMT: 0)

        XCTAssertEqual(details.value(for: .fileSize, dateFormatter: formatter), ByteCountFormatter.string(fromByteCount: 1_024, countStyle: .file))
        XCTAssertEqual(details.value(for: .mimeType, dateFormatter: formatter), "image/png")
        XCTAssertEqual(details.value(for: .fileName, dateFormatter: formatter), name)
        XCTAssertEqual(ChatMessageDetails.Field.fileName.menuValue(name), "…" + String(name.suffix(40)))
        XCTAssertEqual(details.value(for: .resolution, dateFormatter: formatter), "640 × 480")
        XCTAssertEqual(details.value(for: .mediaDataCenter, dateFormatter: formatter), "5")
        XCTAssertNil(ChatMessageDetailsAction.mediaDetails(for: [file], isConcealed: true))
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
        let photoDetails = try XCTUnwrap(ChatMessageDetailsAction.mediaDetails(for: [photo], isConcealed: false))
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
        let videoDetails = try XCTUnwrap(ChatMessageDetailsAction.mediaDetails(for: [moving], isConcealed: false))
        XCTAssertEqual(videoDetails.fileSize, 9_000)
        XCTAssertEqual(videoDetails.mimeType, "video/mp4")
        XCTAssertEqual(videoDetails.dataCenter, 4)
        XCTAssertEqual(videoDetails.dimensions?.width, 400)
        XCTAssertEqual(videoDetails.dimensions?.height, 300)
    }

    func testOmitsUnknownUnsafeOrNonCloudMetadata() {
        let metadata = ChatMessageDetails.MediaDetails(
            fileSize: -1, mimeType: "  ", fileName: "file\u{202E}.png", dimensions: (0, 400), dataCenter: 0
        )
        let details = ChatMessageDetails(id: 1, sentAt: 0, editedAt: nil, forwardedAt: nil, views: nil, forwards: nil, media: metadata)
        let formatter = dateFormatter(secondsFromGMT: 0)
        for field in [ChatMessageDetails.Field.fileSize, .mimeType, .fileName, .resolution, .mediaDataCenter] {
            XCTAssertNil(details.value(for: field, dateFormatter: formatter))
        }
        let local = LocalFileReferenceMediaResource(localFilePath: "/tmp/message-details-test", randomId: 1, size: 12_000)
        let localImage = image(representations: [photoRepresentation(local, width: 800, height: 600)])
        XCTAssertNil(ChatMessageDetailsAction.mediaDetails(for: [localImage], isConcealed: false))
        XCTAssertNil(ChatMessageDetailsAction.mediaDetails(for: [], isConcealed: false))
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

    private func image(representations: [TelegramMediaImageRepresentation], videos: [TelegramMediaImage.VideoRepresentation] = []) -> TelegramMediaImage {
        TelegramMediaImage(
            imageId: MediaId(namespace: Namespaces.Media.CloudImage, id: 1),
            representations: representations,
            videoRepresentations: videos,
            immediateThumbnailData: nil,
            reference: nil,
            partialReference: nil,
            flags: []
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

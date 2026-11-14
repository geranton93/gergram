import Foundation
import XCTest
@testable import ChatUI

final class PluginAttachmentMetadataTests: XCTestCase {
    func testReadsLiteralMetadataAndKeepsURLsAsText() throws {
        let source = #"""
        __id__ = 'example_plugin'
        __name__ = "Example \"Plugin\""
        __author__ = 'Owner\\Account'
        __version__ = '2.4'
        __min_version__ = '12.1.0'
        __requirements__ = 'package>=1, other, '
        __icon__ = 'https://example.com/icon'
        __description__ = (
            "First line\n" # description comment
            '''[Example](https://example.com)
        Last line'''
        )
        raise RuntimeError('this code is never run')
        """#

        let metadata = try PluginAttachmentMetadata.parse(Data(source.utf8)).get()

        XCTAssertEqual(metadata.identifier, "example_plugin")
        XCTAssertEqual(metadata.name, "Example \"Plugin\"")
        XCTAssertEqual(metadata.author, "Owner\\Account")
        XCTAssertEqual(metadata.version, "2.4")
        XCTAssertEqual(metadata.minimumVersion, "12.1.0")
        XCTAssertEqual(metadata.requirements, ["package>=1", "other"])
        XCTAssertEqual(metadata.icon, "https://example.com/icon")
        XCTAssertEqual(metadata.description, "First line\n[Example](https://example.com)\nLast line")
    }

    func testSkipsCommentsStringsNestedAssignmentsAndExpressions() throws {
        let source = #"""
        """
        __id__ = "docstring"
        __name__ = "Docstring"
        """
        # __id__ = "comment"
        if condition:
            __name__ = "Nested"
        call(
        __id__ = "nested_keyword"
        )
        __id__ = "dynamic" + suffix
        __name__ = f"Dynamic {value}"
        __id__ = "actual_id"
        __name__ = 'Настоящее имя'
        __name__ = "Later assignment"
        __author__ = (lookup_author())
        """#

        let metadata = try PluginAttachmentMetadata.parse(Data(source.utf8)).get()

        XCTAssertEqual(metadata.identifier, "actual_id")
        XCTAssertEqual(metadata.name, "Настоящее имя")
        XCTAssertEqual(metadata.version, "1.0")
        XCTAssertNil(metadata.author)
    }

    func testRejectsInvalidMissingAndNonUTF8Metadata() {
        let invalid = [
            "__id__ = '1-invalid'\n__name__ = 'Example'",
            "__id__ = 'x'\n__name__ = 'Example'",
            "__id__ = 'valid_id'\n__name__ = ' '",
            "__id__ = 'valid_id'\n__name__ = '''Unterminated",
            "__id__ = 'valid_id'\n__name__ = 'Example' + suffix",
            "__id__ = 'valid_id'\n__name__ = 'Example'\u{0}"
        ]

        for source in invalid {
            XCTAssertEqual(PluginAttachmentMetadata.parse(Data(source.utf8)), .failure(.invalid))
        }
        XCTAssertEqual(PluginAttachmentMetadata.parse(Data([0xff, 0xfe])), .failure(.invalid))
    }

    func testBoundsInputAndDisplayFields() throws {
        let source = "__id__ = 'valid_id'\n__name__ = '" + String(repeating: "n", count: 101) + "'"
        let data = Data([0xef, 0xbb, 0xbf]) + Data(source.utf8)
        let metadata = try PluginAttachmentMetadata.parse(data).get()

        XCTAssertEqual(metadata.name.count, 100)
        XCTAssertEqual(PluginAttachmentMetadata.parse(Data(repeating: 0x61, count: PluginAttachmentMetadata.maximumFileSize + 1)), .failure(.tooLarge))
    }

    func testReadsOnlyBoundedRegularLocalFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = "__id__ = 'valid_id'\n__name__ = 'Example'"
        let url = directory.appendingPathComponent("cache-id")
        try Data(source.utf8).write(to: url)
        XCTAssertEqual(try PluginAttachmentMetadata.read(from: url).get().identifier, "valid_id")

        let symlink = directory.appendingPathComponent("symlink")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: url)
        XCTAssertEqual(PluginAttachmentMetadata.read(from: symlink), .failure(.unavailable))
        XCTAssertEqual(PluginAttachmentMetadata.read(from: directory), .failure(.unavailable))
        XCTAssertEqual(PluginAttachmentMetadata.read(from: directory.appendingPathComponent("missing")), .failure(.unavailable))

        try Data(repeating: 0x61, count: PluginAttachmentMetadata.maximumFileSize + 1).write(to: url)
        XCTAssertEqual(PluginAttachmentMetadata.read(from: url), .failure(.tooLarge))
    }

    func testRecognizesOnlyPluginSuffix() {
        XCTAssertTrue(PluginAttachmentMetadata.matchesFileName("example.PLUGIN"))
        XCTAssertFalse(PluginAttachmentMetadata.matchesFileName("example.plugin.txt"))
        XCTAssertFalse(PluginAttachmentMetadata.matchesFileName("example.txt"))
        XCTAssertFalse(PluginAttachmentMetadata.matchesFileName(nil))
    }
}

import XCTest
import SwiftSoup

final class DocumentTypeIdentifierWhitespaceTests: XCTestCase {
    private let identifiers = [" ", "\t", "\n", "\r", "\u{000C}", " \t\n "]

    private func document(_ doctype: String, trackingSource: Bool = false) throws -> Document {
        let parser = Parser.htmlParser().settings(ParseSettings(false, false, trackingSource))
        let document = try SwiftSoup.parse(doctype + "<html><head></head><body><p>text</p></body></html>", "", parser)
        document.outputSettings().prettyPrint(pretty: false)
        return document
    }

    private func doctype(in document: Document) throws -> DocumentType {
        try XCTUnwrap(document.getChildNodes().compactMap { $0 as? DocumentType }.first)
    }

    func testParsedWhitespaceOnlyPublicIdentifiersRemainQuoted() throws {
        for identifier in identifiers {
            let document = try document("<!DOCTYPE html PUBLIC \"\(identifier)\">")
            XCTAssertEqual(try doctype(in: document).outerHtml(),
                           "<!DOCTYPE html PUBLIC \"\(identifier)\">")
        }
    }

    func testParsedWhitespaceOnlySystemIdentifiersRemainQuoted() throws {
        for identifier in identifiers {
            let document = try document("<!DOCTYPE html SYSTEM \"\(identifier)\">")
            XCTAssertEqual(try doctype(in: document).outerHtml(),
                           "<!DOCTYPE html SYSTEM \"\(identifier)\">")
        }
    }

    func testWhitespaceOnlyPublicIdentifierDoesNotShiftTheSystemIdentifier() throws {
        for identifier in identifiers {
            let document = try document("<!DOCTYPE html PUBLIC \"\(identifier)\" \"urn:system\">")
            let serialized = try doctype(in: document).outerHtml()
            XCTAssertEqual(serialized, "<!DOCTYPE html PUBLIC \"\(identifier)\" \"urn:system\">")
            let reparsed = try self.document(serialized)
            XCTAssertEqual(try doctype(in: reparsed).attr("publicId"), identifier)
            XCTAssertEqual(try doctype(in: reparsed).attr("systemId"), "urn:system")
        }
    }

    func testWhitespaceOnlySystemIdentifierAfterPublicIdentifierIsPreserved() throws {
        for identifier in identifiers {
            let document = try document("<!DOCTYPE html PUBLIC \"public-name\" \"\(identifier)\">")
            XCTAssertEqual(try doctype(in: document).outerHtml(),
                           "<!DOCTYPE html PUBLIC \"public-name\" \"\(identifier)\">")
        }
    }

    func testNodeCopyPreservesWhitespaceOnlyIdentifiers() throws {
        let document = try document("<!DOCTYPE html PUBLIC \" \" \"\t\">")
        let original = try doctype(in: document)
        let copied = try XCTUnwrap(original.copy() as? DocumentType)
        XCTAssertEqual(try copied.outerHtml(), "<!DOCTYPE html PUBLIC \" \" \"\t\">")
        XCTAssertEqual(try original.outerHtml(), "<!DOCTYPE html PUBLIC \" \" \"\t\">")
    }

    func testChangedBodySerializationPreservesWhitespaceOnlyDoctype() throws {
        for trackingSource in [false, true] {
            let document = try document("<!DOCTYPE html SYSTEM \" \">", trackingSource: trackingSource)
            try document.body()?.attr("data-changed", "true")
            let serialized = String(decoding: try document.outerHtmlUTF8ReusingSourceOutsideBody(), as: UTF8.self)
            let reparsed = try self.documentTypeFromSerializedDocument(serialized)
            XCTAssertEqual(try reparsed.attr("systemId"), " ")
            XCTAssertEqual(try reparsed.outerHtml(), "<!DOCTYPE html SYSTEM \" \">")
        }
    }

    private func documentTypeFromSerializedDocument(_ html: String) throws -> DocumentType {
        let document = try SwiftSoup.parse(html, "", Parser.htmlParser())
        return try doctype(in: document)
    }

    func testExplicitKeyConstructorPreservesWhitespaceOnlyIdentifiers() throws {
        let node = DocumentType(Array("html".utf8), Array("PUBLIC".utf8),
                                Array(" ".utf8), Array("\t".utf8), [])
        XCTAssertEqual(try node.outerHtml(), "<!DOCTYPE html PUBLIC \" \" \"\t\">")
    }

    func testNonemptyIdentifiersAndHTML5DoctypeRemainUnchanged() throws {
        for source in ["<!DOCTYPE html PUBLIC \"public-name\" \"urn:system\">",
                       "<!DOCTYPE html SYSTEM \"urn:system\">"] {
            XCTAssertEqual(try doctype(in: document(source)).outerHtml(), source)
        }
        XCTAssertEqual(try doctype(in: document("<!doctype html>")).outerHtml(), "<!doctype html>")
    }
}

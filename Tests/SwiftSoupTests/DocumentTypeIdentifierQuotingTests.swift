import XCTest
import SwiftSoup

final class DocumentTypeIdentifierQuotingTests: XCTestCase {
    private let quotedValues = [
        "urn:library:\"edition\"", "\"leading", "trailing\"", "\"",
        "日本語-\"版\"-😀", "literal-&quot;-and-\"quote\"",
    ]

    private func document(_ doctype: String, trackingSource: Bool = false) throws -> Document {
        let parser = Parser.htmlParser().settings(ParseSettings(false, false, trackingSource))
        let document = try SwiftSoup.parse(
            doctype + "<html><head></head><body><p>reading</p></body></html>", "", parser
        )
        document.outputSettings().prettyPrint(pretty: false)
        return document
    }

    private func doctype(in document: Document) throws -> DocumentType {
        try XCTUnwrap(document.getChildNodes().compactMap { $0 as? DocumentType }.first)
    }

    private func assertRoundTrip(
        _ declaration: String, publicID: String = "", systemID: String = "",
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let original = try doctype(in: document(declaration))
        XCTAssertEqual(try original.attr("publicId"), publicID, file: file, line: line)
        XCTAssertEqual(try original.attr("systemId"), systemID, file: file, line: line)
        let serialized = try original.outerHtml()
        let reparsed = try doctype(in: document(serialized))
        XCTAssertEqual(try reparsed.attr("publicId"), publicID, file: file, line: line)
        XCTAssertEqual(try reparsed.attr("systemId"), systemID, file: file, line: line)
        XCTAssertEqual(try reparsed.outerHtml(), serialized, file: file, line: line)
    }

    func testParsedSystemIdentifierContainingDoubleQuotesRoundTrips() throws {
        for value in quotedValues {
            try assertRoundTrip("<!DOCTYPE html SYSTEM '\(value)'>", systemID: value)
        }
    }

    func testParsedPublicIdentifierContainingDoubleQuotesRoundTrips() throws {
        for value in quotedValues {
            try assertRoundTrip("<!DOCTYPE html PUBLIC '\(value)'>", publicID: value)
        }
    }

    func testPublicQuotesCannotDiscardTheFollowingSystemIdentifier() throws {
        for value in quotedValues {
            try assertRoundTrip("<!DOCTYPE html PUBLIC '\(value)' \"urn:system\">",
                publicID: value, systemID: "urn:system")
        }
    }

    func testSystemQuotesAfterAPublicIdentifierRoundTrip() throws {
        for value in quotedValues {
            try assertRoundTrip("<!DOCTYPE html PUBLIC \"public-name\" '\(value)'>",
                publicID: "public-name", systemID: value)
        }
    }

    func testBothIdentifiersCanContainDoubleQuotes() throws {
        try assertRoundTrip("<!DOCTYPE html PUBLIC 'public-\"edition\"' 'urn:system-\"edition\"'>",
            publicID: "public-\"edition\"", systemID: "urn:system-\"edition\"")
    }

    func testEachIdentifierChoosesItsOwnDelimiter() throws {
        try assertRoundTrip("<!DOCTYPE html PUBLIC 'public-\"edition\"' \"urn:system-'edition'\">",
            publicID: "public-\"edition\"", systemID: "urn:system-'edition'")
        try assertRoundTrip("<!DOCTYPE html PUBLIC \"public-'edition'\" 'urn:system-\"edition\"'>",
            publicID: "public-'edition'", systemID: "urn:system-\"edition\"")
    }

    func testApostropheOnlyIdentifiersKeepDoubleQuotedOutput() throws {
        let source = "<!DOCTYPE html PUBLIC \"public-'edition'\" \"urn:system-'edition'\">"
        XCTAssertEqual(try doctype(in: document(source)).outerHtml(), source)
        try assertRoundTrip(source, publicID: "public-'edition'", systemID: "urn:system-'edition'")
    }

    func testLiteralCharacterReferenceSpellingIsNotUsedAsAnEscape() throws {
        let value = "&quot;&#34;\"&apos;&#39;"
        let source = "<!DOCTYPE html SYSTEM '\(value)'>"
        XCTAssertEqual(try doctype(in: document(source)).outerHtml(), source)
        try assertRoundTrip(source, systemID: value)
    }

    func testConvenienceConstructorsChooseASafeDelimiter() throws {
        let system = DocumentType("html", "", "urn:\"edition\"", "")
        XCTAssertEqual(try system.outerHtml(), "<!DOCTYPE html SYSTEM 'urn:\"edition\"'>")
        let publicAndSystem = DocumentType("html", "public-\"edition\"", "urn:'edition'", "")
        XCTAssertEqual(try publicAndSystem.outerHtml(),
            "<!DOCTYPE html PUBLIC 'public-\"edition\"' \"urn:'edition'\">")
    }

    func testExplicitKeywordConstructorChoosesASafeDelimiter() throws {
        let node = DocumentType(Array("html".utf8), Array("PUBLIC".utf8),
            Array("public-\"edition\"".utf8), Array("urn:system-\"edition\"".utf8), [])
        XCTAssertEqual(try node.outerHtml(),
            "<!DOCTYPE html PUBLIC 'public-\"edition\"' 'urn:system-\"edition\"'>")
    }

    func testCopiesPreserveIdentifierBytesAndQuotation() throws {
        let source = "<!DOCTYPE html PUBLIC 'public-\"edition\"' 'urn:system-\"edition\"'>"
        let original = try doctype(in: document(source))
        let copy = try XCTUnwrap(original.copy() as? DocumentType)
        let parentCopy = try XCTUnwrap(original.copy(parent: nil) as? DocumentType)
        for node in [original, copy, parentCopy] {
            XCTAssertEqual(try node.outerHtml(), source)
            XCTAssertEqual(try node.attr("publicId"), "public-\"edition\"")
            XCTAssertEqual(try node.attr("systemId"), "urn:system-\"edition\"")
        }
    }

    func testChangedBodySerializationRetainsQuotedIdentifiers() throws {
        for trackingSource in [false, true] {
            let source = "<!DOCTYPE html PUBLIC 'public-\"edition\"' 'urn:system-\"edition\"'>"
            let native = try document(source, trackingSource: trackingSource)
            try native.body()?.attr("data-changed", "true")
            let serialized = String(decoding: try native.outerHtmlUTF8ReusingSourceOutsideBody(), as: UTF8.self)
            let reparsed = try SwiftSoup.parse(serialized)
            XCTAssertEqual(try doctype(in: reparsed).attr("publicId"), "public-\"edition\"")
            XCTAssertEqual(try doctype(in: reparsed).attr("systemId"), "urn:system-\"edition\"")
            XCTAssertEqual(try reparsed.body()?.attr("data-changed"), "true")
            XCTAssertEqual(try reparsed.body()?.text(), "reading")
        }
    }

    func testXMLSystemLiteralAlsoPreservesDoubleQuotes() throws {
        let source = "<!DOCTYPE root SYSTEM 'urn:library:\"edition\"'><root>text</root>"
        let native = try SwiftSoup.parse(source, "", Parser.xmlParser())
        native.outputSettings().syntax(syntax: .xml).prettyPrint(pretty: false)
        let serialized = try native.outerHtml()
        let reparsed = try SwiftSoup.parse(serialized, "", Parser.xmlParser())
        XCTAssertEqual(try doctype(in: reparsed).attr("systemId"), "urn:library:\"edition\"")
    }

    func testOrdinaryHTML5AndWhitespaceIdentifiersKeepTheirOutput() throws {
        for source in ["<!doctype html>",
                       "<!DOCTYPE html SYSTEM \"urn:system\">",
                       "<!DOCTYPE html PUBLIC \"public-name\" \"urn:system\">",
                       "<!DOCTYPE html PUBLIC \" \" \"\t\">"] {
            XCTAssertEqual(try doctype(in: document(source)).outerHtml(), source)
        }
    }
}

import Foundation
import XCTest
import SwiftSoup

final class HtmlTemplateTreeConstructionTests: XCTestCase {
    private func parse(_ content: String, tracking: Bool = false, head: String = "") throws -> Document {
        let parser = Parser.htmlParser().settings(ParseSettings(false, false, tracking))
        let document = try SwiftSoup.parse("<!doctype html><html><head>" + head
            + "</head><body>" + content + "</body></html>", "https://example.invalid/source/", parser)
        document.outputSettings().prettyPrint(pretty: false)
        return document
    }

    private func node(_ document: Document, _ id: String,
                      file: StaticString = #filePath, line: UInt = #line) throws -> Element {
        try XCTUnwrap(document.getElementById(id), "Missing \(id)", file: file, line: line)
    }

    private func templateAncestor(_ element: Element) -> Element? {
        var parent = element.parent()
        while let current = parent {
            if current.tagNameNormal() == "template" { return current }
            parent = current.parent()
        }
        return nil
    }

    private func assertBoundary(_ content: String, draftIDs: [String] = ["draft"],
                                liveIDs: [String] = ["after"],
                                file: StaticString = #filePath, line: UInt = #line) throws {
        for tracking in [false, true] {
            let document = try parse(content, tracking: tracking)
            for id in draftIDs {
                XCTAssertNotNil(templateAncestor(try node(document, id, file: file, line: line)),
                                "\(id) escaped its template; tracking=\(tracking)", file: file, line: line)
            }
            for id in liveIDs {
                XCTAssertNil(templateAncestor(try node(document, id, file: file, line: line)),
                             "\(id) was swallowed by a template; tracking=\(tracking)", file: file, line: line)
            }
            // Mutating the body forces the Reader-style serialization boundary.
            // Reparse with the real dependency, not a substitute DOM.
            try document.body()?.attr("data-mutated", "true")
            let bytes = try document.outerHtmlUTF8ReusingSourceOutsideBody()
            let reparsed = try SwiftSoup.parse(bytes, "", Parser.htmlParser())
            for id in draftIDs {
                XCTAssertNotNil(templateAncestor(try node(reparsed, id, file: file, line: line)),
                                "Serialized \(id) escaped", file: file, line: line)
            }
            for id in liveIDs {
                XCTAssertNil(templateAncestor(try node(reparsed, id, file: file, line: line)),
                             "Serialized \(id) became inert", file: file, line: line)
            }
        }
    }

    func testBlockStartsDoNotCloseAnOuterParagraphThroughTemplate() throws {
        for tag in ["p", "div", "section", "article"] {
            for close in ["</\(tag)>", ""] {
                try assertBoundary("<p id=outer>before<template><\(tag) id=draft>draft"
                    + close + "</template>tail</p><p id=after>after</p>", liveIDs: ["outer", "after"])
            }
        }
    }

    func testListStartsRespectTemplateScope() throws {
        for (list, item) in [("ul", "li"), ("ol", "li"), ("dl", "dd"), ("dl", "dt")] {
            try assertBoundary("<\(list)><\(item) id=outer>before<template><\(item) id=draft>draft"
                + "</template>tail</\(item)><\(item) id=after>after</\(item)></\(list)>",
                liveIDs: ["outer", "after"])
        }
    }

    func testStrayEndTagsCannotCloseOuterElements() throws {
        for tag in ["p", "div", "section", "ul"] {
            try assertBoundary("<\(tag) id=outer>before<template></\(tag)><span id=draft>draft</span>"
                + "</template>tail</\(tag)><p id=after>after</p>", liveIDs: ["outer", "after"])
        }
    }

    func testUnclosedFormattingDoesNotLeakIntoFollowingLiveContent() throws {
        try assertBoundary("<p>before<template><b id=draft>draft</template>tail</p><p id=after>after</p>")
        let document = try parse("<template><b id=draft>draft</template><p id=after>after</p>")
        XCTAssertEqual(try document.select("b").count, 1)
        XCTAssertEqual(try node(document, "after").parent()?.tagNameNormal(), "body")
    }

    func testOuterFormattingSurvivesTemplateClosure() throws {
        for tracking in [false, true] {
            let document = try parse("<b id=outer>before<template><i id=draft>draft</template>tail</b><p id=after>after</p>", tracking: tracking)
            XCTAssertEqual(try node(document, "outer").ownText(), "beforetail")
            XCTAssertNotNil(templateAncestor(try node(document, "draft")))
            XCTAssertEqual(try document.select("i").count, 1)
            XCTAssertNil(templateAncestor(try node(document, "after")))
        }
    }

    func testNestedTemplatesRestoreTheEnclosingTemplateMode() throws {
        try assertBoundary("<p>before<template id=one><p id=draft>one<template id=two><p id=nested>two"
            + "</template><span id=innerTail>tail</span></template>live</p><p id=after>after</p>",
            draftIDs: ["draft", "nested", "innerTail"])
        let document = try parse("<template id=one><template id=two><p id=nested>x</template>"
            + "<span id=innerTail>y</span></template><p id=after>z</p>")
        XCTAssertEqual(templateAncestor(try node(document, "nested"))?.id(), "two")
        XCTAssertEqual(templateAncestor(try node(document, "innerTail"))?.id(), "one")
    }

    func testSelfClosingTemplateSyntaxDoesNotExposeFollowingContents() throws {
        try assertBoundary("<p>before<template/><p id=draft>draft</template>tail</p><p id=after>after</p>")
    }

    func testTemplateRowsDoNotEscapeAnOuterTable() throws {
        for prefix in ["<table>", "<table><tbody>", "<table><tbody><tr>", "<table><colgroup>"] {
            try assertBoundary(prefix + "<template><tr><td id=draft>draft</td></tr></template></table><p id=after>after</p>")
        }
    }

    func testTemplateInsertionModesKeepDirectTableChildren() throws {
        for content in ["<caption id=draft>caption", "<colgroup id=draft><col>", "<col id=draft>",
                        "<tbody id=draft><tr><td>cell", "<tr id=draft><td>cell", "<td id=draft>cell", "<th id=draft>cell"] {
            try assertBoundary("<template>" + content + "</template><p id=after>after</p>")
        }
    }

    func testColumnModeCannotPopTheTemplateForStrayContent() throws {
        try assertBoundary("<template><col id=draft>ignored</colgroup><p>ignored</template><p id=after>after</p>")
    }

    func testFosterParentingKeepsTheNativeTextOrderInsideTemplate() throws {
        for tracking in [false, true] {
            let document = try parse("<template id=tpl><table id=table>before<div id=draft>draft</div>after"
                + "<tr><td>cell</td></tr></table></template><p id=after>after</p>", tracking: tracking)
            let template = try node(document, "tpl")
            let outline = template.getChildNodes().map { child -> String in
                if let text = child as? TextNode { return text.getWholeText() }
                return (child as? Element)?.tagNameNormal() ?? "other"
            }
            XCTAssertEqual(outline, ["before", "div", "after", "table"])
            XCTAssertEqual(try node(document, "table").text(), "cell")
            XCTAssertNil(templateAncestor(try node(document, "after")))
        }
    }

    func testFosterParentingPrefersTemplateOverAnOuterTable() throws {
        try assertBoundary("<table><template>before<div id=draft>draft</div>after</template>"
            + "<tr><td id=after>after</td></tr></table>")
    }

    func testTemplatesCanCloseThroughOpenCellsAndFormatting() throws {
        try assertBoundary("<b id=outer>before<template><table><tr><td><i id=draft>draft"
            + "</template>tail</b><p id=after>after</p>", liveIDs: ["outer", "after"])
    }

    func testNestedFormDoesNotReplaceTheDocumentFormPointer() throws {
        for tracking in [false, true] {
            let document = try parse("<form id=outer><input id=before><template><form id=inner>"
                + "<input id=draft></form></template><input id=after></form>", tracking: tracking)
            let outer = try XCTUnwrap(node(document, "outer") as? FormElement)
            let inner = try XCTUnwrap(node(document, "inner") as? FormElement)
            XCTAssertEqual(outer.elements().array().map { $0.id() }, ["before", "after"])
            XCTAssertEqual(inner.elements().array().map { $0.id() }, ["draft"])
        }
    }

    func testStrayFormEndCannotClearTheOuterFormPointer() throws {
        for tracking in [false, true] {
            let document = try parse("<form id=outer><template></form><input id=draft></template><input id=after></form>", tracking: tracking)
            let outer = try XCTUnwrap(node(document, "outer") as? FormElement)
            XCTAssertEqual(outer.elements().array().map { $0.id() }, ["after"])
        }
    }

    func testFormInTemplateTableIsPreservedWithoutReplacingOuterPointer() throws {
        try assertBoundary("<template><table><form id=draft></form></table></template><p id=after>after</p>")
    }

    func testTemplateBodyAndHTMLTagsCannotChangeLiveRootAttributes() throws {
        for tracking in [false, true] {
            let document = try parse("<template><html id=inertHTML><body id=inertBody><p id=draft>draft"
                + "</template><p id=after>after</p>", tracking: tracking)
            XCTAssertEqual(document.body()?.id(), "")
            XCTAssertNil(try document.getElementById("inertHTML"))
            XCTAssertNil(try document.getElementById("inertBody"))
            XCTAssertNil(templateAncestor(try node(document, "after")))
        }
    }

    func testInertBaseDoesNotChangeLiveLinkResolution() throws {
        let document = try parse("<template><base href='https://other.invalid/'></template><a id=after href=relative>link</a>")
        XCTAssertEqual(try node(document, "after").absUrl("href"), "https://example.invalid/source/relative")
    }

    func testTemplateInsideSelectRetainsItsContentsAndFollowingOption() throws {
        try assertBoundary("<select><template><div id=draft>draft</div></template><option id=after>after</option></select>")
        try assertBoundary("<template><select><option id=draft>draft</template><p id=after>after</p>")
    }

    func testTemplateInHeadDoesNotConsumeFollowingMetadataOrBody() throws {
        for tracking in [false, true] {
            let document = try parse("<p id=after>after</p>", tracking: tracking,
                head: "<template id=tpl><p id=draft>draft</template><meta id=meta name=x content=y>")
            XCTAssertTrue(try node(document, "tpl").parent() === document.head())
            XCTAssertTrue(try node(document, "meta").parent() === document.head())
            XCTAssertNil(templateAncestor(try node(document, "after")))
        }
    }

    func testTemplateAfterClosedHeadSurvivesSourceReuse() throws {
        for tracking in [false, true] {
            let parser = Parser.htmlParser().settings(ParseSettings(false, false, tracking))
            let document = try SwiftSoup.parse("<!doctype html><html><head></head>"
                + "<template id=tpl><p id=draft>draft</template><body><p id=after>after</p></body></html>", "", parser)
            XCTAssertTrue(try node(document, "tpl").parent() === document.head())
            try document.body()?.attr("data-mutated", "true")
            let reparsed = try SwiftSoup.parse(document.outerHtmlUTF8ReusingSourceOutsideBody(), "", Parser.htmlParser())
            XCTAssertTrue(try node(reparsed, "tpl").parent() === reparsed.head())
            XCTAssertNotNil(templateAncestor(try node(reparsed, "draft")))
            XCTAssertNil(templateAncestor(try node(reparsed, "after")))
        }
    }

    func testEOFClosesNestedTemplatesWithoutLeakingTheirContents() throws {
        for tail in ["<p id=draft>draft", "<template><b id=draft>draft", "<table><tr><td id=draft>draft", "<col id=draft>"] {
            try assertBoundary("<p id=after>before</p><template>" + tail)
        }
    }

    func testTemplateFragmentContextUsesTableInsertionModes() throws {
        for content in ["<tr id=draft><td>cell</td></tr>", "<td id=draft>cell</td>", "<col id=draft>"] {
            let document = try parse("<template id=tpl></template><p id=after>after</p>")
            let template = try node(document, "tpl")
            try template.html(content)
            XCTAssertTrue(try node(document, "draft").parent() === template)
            XCTAssertNil(templateAncestor(try node(document, "after")))
        }
    }

    func testRawTextDoesNotInterpretTemplateDelimiters() throws {
        for tag in ["style", "script"] {
            let document = try parse("<template><\(tag) id=draft>\"</template>\"</\(tag)></template><p id=after>after</p>")
            XCTAssertNotNil(templateAncestor(try node(document, "draft")))
            XCTAssertNil(templateAncestor(try node(document, "after")))
            XCTAssertEqual(try document.select("template").count, 1)
        }
    }

    func testXMLParsingDoesNotAdoptHTMLTemplateRules() throws {
        let document = try SwiftSoup.parse("<root><p id=outer><template/><p id=after>x</p></p></root>", "", Parser.xmlParser())
        XCTAssertEqual(try node(document, "after").parent()?.id(), "outer")
        XCTAssertEqual(try document.select("template").first()?.getChildNodes().count, 0)
    }

    func testNonTemplateParagraphAndFormControlsRemainUnchanged() throws {
        let document = try parse("<p id=first>a</p><p id=after>b</p><form id=form><input id=control></form>")
        XCTAssertEqual(try node(document, "first").parent()?.tagNameNormal(), "body")
        XCTAssertEqual(try node(document, "after").parent()?.tagNameNormal(), "body")
        let form = try XCTUnwrap(node(document, "form") as? FormElement)
        XCTAssertEqual(form.elements().array().map { $0.id() }, ["control"])
    }
}

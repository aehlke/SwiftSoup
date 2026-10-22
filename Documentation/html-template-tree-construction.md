# HTML template tree-construction boundary

## Failure

A template inside a paragraph or list item must not let its child start/end
tags close elements outside the template. Likewise, closing an incomplete
template must not hide following live content or leak active formatting into it.

For example:

```html
<p>visible<template><p>draft</template>tail</p><p>after</p>
```

Without template-aware tree construction, the draft paragraph can move outside
the template. Adding a scope boundary alone can fail in the opposite direction:
the following live paragraph remains inside the template. Ancestor filtering
after parsing cannot reconstruct an inert boundary already lost by the parser.

## Implementation

The HTML tree builder keeps a stack of template insertion modes, places an
active-formatting marker on entry, and restores the enclosing mode on closure
or end of input. Template boundaries participate in the existing scope and
table-stack rules. Table-related first children select their appropriate
insertion modes instead of being handled as ordinary body content.

Template closure is dispatched through the appropriate insertion-mode states.
It is not intercepted ahead of pending table text. Column-group recovery must
not pop the template when no real column group is current. Foster-parented
content remains inside the innermost relevant template and preserves the
native text order around an inner table.

Source-preserving serialization is part of this boundary. Relocating table
content invalidates stale table source slices; late head content invalidates
the already-closed head slice. Otherwise a correct-looking native tree can
serialize the old order or omit the inserted template.

An inner template form does not replace the outer document form pointer.
Form controls inside a template are associated only with a form inside that
template tree. Template-contained base, body and html tags do not change the
live document's base URI or root attributes.

## Regression tests

`HtmlTemplateTreeConstructionTests` exercises the real parser and serializer.
It covers closed/unclosed block and list children, stray end tags, nested
templates, formatting isolation, table/column/foster handling, forms, base
URIs, select/head insertion, EOF, template-context fragments, raw text, and
unchanged XML/plain-HTML controls.

Tests also mutate the body and reparse `outerHtmlUTF8ReusingSourceOutsideBody`
output, with source tracking enabled and disabled. In a complete checkout, run
the existing test target, for example:

```sh
swift test --filter HtmlTemplateTreeConstructionTests
```

The focused browser comparison is complementary: it compares complete head
and body trees, template content fragments, attributes, document mode, and
ordinary live IDs before and after actual native serialization. Passing text
lengths alone would miss swallowed live nodes, changed formatting, or dropped
head content.

## Scope

This implements an HTML parsing/serialization boundary within SwiftSoup's
existing tree representation. It does not introduce a native DocumentFragment
or change SwiftSoup selectors/text APIs to hide template descendants. Consumers
requiring ordinary browser-document membership must still handle that distinction.

Full foreign-content namespace processing, declarative shadow roots, all legacy
DOCTYPE/document-mode rules, and general serializer equivalence are separate
contracts. XML parsing is unchanged. Do not infer those behaviors from the
focused HTML cases.

For Reader integration, retain strict native subject/completeness and Undo
validation. Qualify the actual preprocessing and metadata path, then section
Mark, original Undo and Mark All. The dependency-level tests do not execute those
commands or establish a shipping application qualification.

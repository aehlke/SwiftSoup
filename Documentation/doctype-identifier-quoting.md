# Preserve literal quotes in DOCTYPE identifiers

A single-quoted PUBLIC or SYSTEM identifier can contain a literal double quote.
The tokenizer preserves that value, but serializing every identifier between
double quotes closes it early on reparse. PUBLIC identifiers can then lose the
following system identifier and force the browser into quirks mode.

For example:

```html
<!DOCTYPE html PUBLIC 'public-"edition"' "urn:system">
```

Previously this became:

```html
<!DOCTYPE html PUBLIC "public-"edition"" "urn:system">
```

In a browser round trip this truncates the public identifier to `public-`, drops
`urn:system`, and changes CSS1Compat to BackCompat. With an earlier uppercase
`PAGE` class and a later lowercase `page`, `.page` therefore selects a different
root. This matters to consumers which prepare native sections before rendering
serialized HTML; it does not establish a durable reading mutation or a customer
incident.

## Correction

Choose a delimiter independently for each identifier. Use a single quote when
the value contains a double quote but no single quote; retain the existing
double-quoted output otherwise. Do not entity-escape the value: DOCTYPE parsing
does not decode character references inside these identifiers. See the
[HTML tokenizer's DOCTYPE states](https://html.spec.whatwg.org/multipage/parsing.html#doctype-public-identifier-(single-quoted)-state).

The shared helper changes only quotation in serialization. The whitespace-only
identifier repair remains intact. Ordinary identifiers, names, PUBLIC/SYSTEM
keywords, parser modes, constructors and copy semantics retain their existing
contracts. The helper reads ByteSlice directly without constructing another
identifier string.

A manually constructed identifier containing both delimiters cannot be encoded
losslessly by choosing either delimiter. This change retains its old
serialization behavior rather than inventing an escape or removing bytes.
Explicitly empty versus absent identifiers and comprehensive document-mode
handling are separate issues, not fixed here.

## Regression coverage

`DocumentTypeIdentifierQuotingTests` exercises parsing, serialization and
reparsing, both identifier positions, independent delimiter selection, leading
and trailing quotes, Unicode, literal character-reference spellings, public
constructors, copies, HTML/XML output, and changed-body serialization with source
tracking off and on. Assertions inspect output and parsed values, not repository
source text. Ordinary HTML5 and whitespace identifiers remain controls.

Run through the existing SwiftSoup test target, for example:

```sh
swift test --filter DocumentTypeIdentifierQuotingTests
```

A consumer's full native processing, command admission and browser integration
still require that consumer's own tests. Dependency round-trip coverage is not
application or storage qualification.

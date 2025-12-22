# just-koka-html — spec + plan

## Goal

Build a **pure Koka** HTML5 parsing library (no external runtime deps) inspired by the Python reference in `./justhtml`, and make it pass the selected cases from `./html5lib-tests` (selection controlled by `./data/html5lib_allowlists.json`). External tools (Python/Make/Ninja) are allowed for building and testing.

This repo already includes:
- `./justhtml`: a minimal Python HTML5 implementation to use as API and behavior inspiration.
- `./html5lib-tests`: upstream conformance tests (tree construction + tokenizer, plus other suites).
- `./tools/html5lib_allowlists*.py`: tooling for allowlists / coverage diffs.

---

## User-facing API (Koka)

### Design goals
- Familiar surface area vs `justhtml` (parse → result with `root` + `errors`).
- Koka-idiomatic: algebraic data types + records, total/pure interfaces by default, internal local mutation allowed behind the scenes.
- Support both:
  - **Tree-building** (html5lib tree-construction tests).
  - **Tokenizer** (html5lib tokenizer tests).

### Public modules
Proposed module layout (Koka files under `src/`):
- `html5` (facade): `parse`, `parse-fragment`, `tokenize`, `to-test-format`.
- `html5/dom`: DOM representation and traversal helpers.
- `html5/tokenizer`: tokenizer state machine + token types.
- `html5/treebuilder`: tree construction algorithm + insertion modes.
- `html5/serialize`: html5lib “test format” serializer (tree dump).
- `html5/encoding` (later): byte input + encoding sniffing (html5lib encoding tests).

### Core types

#### Namespaces
We need namespaces for element names and attribute names, because html5lib-tests’ tree dump requires prefixes like `svg ` / `math ` and attribute prefixes like `xlink ` / `xml ` / `xmlns `.

```koka
type Namespace = Html | Svg | Math
type AttrNamespace = None | XLink | Xml | Xmlns
type QName = { ns: Namespace, local: string }
type AttrName = { ns: AttrNamespace, local: string }
type Attr = { name: AttrName, value: string }  // value may be "" for boolean attrs
```

#### DOM representation (arena-based)
To avoid parent pointers and enable efficient incremental building, represent the DOM as an **arena** of nodes with child lists of `NodeId`.

```koka
type NodeId = int

type Doctype = {
  name: string,
  publicId: maybe<string>,
  systemId: maybe<string>,
  forceQuirks: bool
}

type Node =
  | Document( children: list<NodeId>, quirksMode: string )
  | DocumentFragment( children: list<NodeId>, context: maybe<FragmentContext> )
  | Element( name: string, ns: Namespace, attrs: list<Attr>, children: list<NodeId> )
  | Template( ns: Namespace, attrs: list<Attr>, children: list<NodeId>, content: NodeId )
  | Text( data: string )
  | Comment( data: string )
  | DoctypeNode( doctype: Doctype )

type Dom = { nodes: vector<Node>, root: NodeId }
```

Notes:
- `Template` needs a separate `content` node because html5lib’s tree dump prints a synthetic `content` section.
- We store attributes as a list; `to-test-format` will sort by the **display name** as required by html5lib-tests.

#### Parse API types

```koka
type FragmentContext = { tag: string, ns: Namespace }  // ns default Html

type ParseError = { code: string, line: int, col: int }

type ParseOptions = {
  collectErrors: bool,
  strict: bool,
  scriptingEnabled: bool,
  iframeSrcdoc: bool
  // later: transportEncoding: maybe<string>
}

type ParseResult = { dom: Dom, errors: list<ParseError> }
```

### Public functions

#### Parsing
```koka
pub fun parse(html: string, opts: ParseOptions = defaultParseOptions) : ParseResult
pub fun parse-fragment(html: string, context: FragmentContext, opts: ParseOptions = defaultParseOptions) : ParseResult
```

Behavior (eventual, matching html5lib expectations):
- `parse` runs preprocessing + tokenizer + treebuilder, returns a `#document` root.
- `parse-fragment` uses the fragment parsing algorithm with the provided context element.

`strict=true` (later) should fail fast on the first parse error (Koka `exn`), but html5lib-tests mostly count errors rather than inspect messages; strict mode is mainly a user feature.

#### Tokenization (for tokenizer tests)
```koka
type Token =
  | TokDoctype(name: string, publicId: maybe<string>, systemId: maybe<string>, forceQuirks: bool)
  | TokStartTag(name: string, attrs: list<Attr>, selfClosing: bool)
  | TokEndTag(name: string)
  | TokComment(data: string)
  | TokCharacter(data: string)
  | TokEOF

type TokenizerState = Data | PLAINTEXT | RCDATA | RAWTEXT | ScriptData | CDATASection

pub fun tokenize(html: string, initial: TokenizerState = Data, lastStartTag: maybe<string> = Nothing)
  : (tokens: list<Token>, errors: list<ParseError>)
```

Token output must coalesce adjacent character tokens like the upstream tests require.

#### Serialization for test validation
```koka
pub fun to-test-format(dom: Dom) : string
```

This prints the html5lib tree dump format described in `html5lib-tests/tree-construction/README.md`.

---

## Internal architecture

### Tokenizer
- Pure state machine closely following the HTML Standard tokenizer states.
- Emits `Token`s and records errors with 1-based `(line,col)`.
- Needs “input stream preprocessing” (CRLF normalization, NUL handling) as required by tokenizer tests.

### Treebuilder
- Consumes tokens to build `Dom`.
- Maintains:
  - stack of open elements
  - active formatting elements
  - insertion mode stack (including template modes)
  - flags: frameset-ok, foster parenting, etc.
- Must support scripting on/off mode (tests specify `#script-on/off`).

### Arena allocation strategy (Koka)
Even in “pure Koka”, we can use local mutation internally:
- Build `vector<Node>` in `st`/`ref` effects internally, but return an immutable `Dom`.
- Keep the public API pure and deterministic.

---

## Test harness + allowlists

### Allowlists
The test runner will select enabled cases from:
- `./data/html5lib_allowlists.json`

Tooling:
- `./tools/html5lib_allowlists_cli.py stats`
- `./tools/html5lib_allowlists_cli.py diff-prev`
- `./tools/html5lib_allowlists_cli.py diff-prev --fail-on-decrease`

Standard: **every commit message** should include the output of `./tools/html5lib_allowlists_cli.py diff-prev`.

### Test runner (external)
We’ll use Python to:
- Read fixtures from `html5lib-tests/`.
- For each enabled case:
  - Invoke a compiled Koka runner executable (CLI) that performs:
    - tokenizer run → JSON-ish output or line-based tokens
    - tree construction run → `to-test-format` output
  - Compare to expected output.

This avoids needing a JSON parser in Koka early on.

---

## CI (GitHub Actions)

We will add:
- A workflow that checks out submodules and installs Koka:
  - `curl -sSL https://github.com/koka-lang/koka/releases/latest/download/install.sh | sh`
- Runs the test suite (the Python test runner).
- Runs `./tools/html5lib_allowlists_cli.py diff-prev --fail-on-decrease` to prevent coverage regressions.

---

# Milestones

## Milestone 0 (bare-bones, smoke test)
**Goal:** a tiny vertical slice: parse one simple HTML string and return the expected DOM dump.

Deliverables:
1. Minimal Koka modules:
   - `html5/dom` with `Dom`, `Node`, constructors, child accessors.
   - `html5/serialize` with `to-test-format` for Document + Element + Text.
   - `html5` facade with `parse` returning `ParseResult`.
2. Minimal parser:
   - Not full HTML5 yet; just enough to parse a single well-formed example with explicit tags.
   - Handle: start tags, end tags, text nodes.
   - Assumption for M0: input is well-formed and explicitly contains `<html><head>...</head><body>...</body></html>`.
3. Single smoke test:
   - Example input:
     - `<html><head></head><body><p>Hello</p></body></html>`
   - Expected `to-test-format`:
     ```
     | <html>
     |   <head>
     |   <body>
     |     <p>
     |       "Hello"
     ```
4. Test harness:
   - A Python script (e.g. `tools/run_tests.py`) that:
     - builds the Koka runner
     - runs the smoke test and exits non-zero on mismatch

Exit criteria:
- `parse(example).dom |> to-test-format` matches expected exactly.

## Milestone 1 (tokenizer correctness slice)
- Implement HTML5 tokenizer states needed for a small allowlisted subset.
- Add CLI mode to run tokenizer tests and emit comparable output.
- Start enabling a handful of tokenizer cases in `html5lib_allowlists.json`.

## Milestone 2 (treebuilder core)
- Implement insertion modes and implied elements for common cases.
- Add support for `#document-fragment` and fragment contexts.
- Enable a small set of tree-construction doc + fragment cases.

## Milestone 3 (foreign content + templates)
- SVG/Math integration points, adjusted tag/attribute names, template handling.
- Expand allowlists in foreign + template fixtures.

## Milestone 4 (errors + locations)
- Accurate parse error codes and 1-based locations (tokenizer + treebuilder).
- Ensure tree-construction tests’ error counts match.

## Milestone 5 (encoding + byte input)
- Encoding sniffing + overrides, pass `html5lib-tests/encoding` (if included in our runner).
- Decide public API for `parse-bytes` once Koka byte/string story is clear.

## Milestone 6 (scale up coverage)
- Iterate: fix behavior → expand allowlists → keep CI green.
- Track progress with `allowlists.diff-prev.txt` per commit.

---
```

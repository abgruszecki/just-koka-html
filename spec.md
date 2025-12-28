# just-koka-html — spec + plan

## Goal

Build a **pure Koka** HTML5 parsing library (no external runtime deps) inspired by the Python reference in `./justhtml`, and make it pass the selected cases from `./html5lib-tests` (selection controlled by `./data/html5lib_allowlists.json`). External tools (Python/Make/Ninja) are allowed for building and testing.

This repo already includes:
- `./justhtml`: a minimal Python HTML5 implementation to use as API and behavior inspiration.
- `./html5lib-tests`: upstream conformance tests (tree construction + tokenizer, plus other suites).
- `./tools/html5lib_allowlists*.py`: tooling for allowlists / coverage diffs.

---

## Status (this repo)

As of the current `master`:
- Koka runner CLI exists (`src/cli.kk`) and is driven by Python harnesses (`tools/run_html5lib_tests.py`, `tools/run_encoding_tests.py`).
- Tokenizer tests: passing with `data/html5lib_allowlists.json` enabling 100% of tokenizer fixtures.
- Tree construction tests: passing for the currently enabled allowlisted subsets; coverage is still partial and is expected to grow over time.
- Encoding sniffing: passing the encoding fixture set used by `tools/run_encoding_tests.py`.

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

## Koka compiler source repo

This repo contains the `./koka` submodule for reference only.

- For local development and for this repo’s scripts/tests, use the `koka` compiler already installed and available on `PATH`.
- Do not build or invoke the compiler from the `./koka` submodule as part of normal builds/tests.

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

Status: ✅ Done (runner smoke test exists and passes via `tools/run_tests.py`).

## Milestone 1 (tokenizer correctness slice)
- Implement HTML5 tokenizer states needed for a small allowlisted subset.
- Add CLI mode to run tokenizer tests and emit comparable output.
- Start enabling a handful of tokenizer cases in `html5lib_allowlists.json`.

Status: ✅ Done (tokenizer harness passes with allowlists enabling all tokenizer fixtures).

## Milestone 2 (treebuilder core)
- Implement insertion modes and implied elements for common cases.
- Add support for `#document-fragment` and fragment contexts.
- Enable a small set of tree-construction doc + fragment cases.

Status: 🚧 In progress (treebuilder passes enabled allowlists; remaining work is expanding coverage toward 100%).

## Milestone 3 (foreign content + templates)
- SVG/Math integration points, adjusted tag/attribute names, template handling.
- Expand allowlists in foreign + template fixtures.

## Milestone 4 (errors + locations)
- Accurate parse error codes and 1-based locations (tokenizer + treebuilder).
- Ensure tree-construction tests’ error counts match.
 - **Implementation note (Koka)**: avoid relying on nested helper functions that capture locally-mutable state for error sinks/positions; prefer threading error state explicitly (e.g. as part of the treebuilder state) so the compiler doesn’t need to generalize heap-parameterized `local` effects.

## Milestone 5 (encoding + byte input)
- Encoding sniffing + overrides, pass `html5lib-tests/encoding` (if included in our runner).
- Decide public API for `parse-bytes` once Koka byte/string story is clear.

## Milestone 6 (scale up coverage)
- Iterate: fix behavior → expand allowlists → keep CI green.
- Track progress with `allowlists.diff-prev.txt` per commit.
- Status: done for the current baseline (auto-allowlist in place; `diff-prev --fail-on-decrease` green; allowlists at `1078/1590` doc + `101/192` frag).

---

## Milestone Execution Plan

Guiding principles:
- Prefer **vertical slices**: add one missing behavior end-to-end (tokenize → treebuild → serialize → allowlist → CI) per commit.
- Keep the public API stable; refactor internals aggressively as needed.
- Expand allowlists only when the behavior is deterministic and the diff tool stays green.

### M0 (done)
- Keep the smoke test (`tools/run_tests.py`) as the “can we build/run at all?” gate.

### M1 (tokenizer correctness slice)
1. Expand tokenizer coverage in this order (each as its own commit series):
   - Markup declarations: `<!-- -->`, `<!DOCTYPE ...>` (enables many tree tests too).
   - Rawtext/RCDATA/script/PLAINTEXT switching (driven by treebuilder start tags).
   - Character references: spec-correct edge cases + attribute-value context.
   - Error reporting hooks (record code + location; tests mostly check counts first).
2. Improve the runner protocol to support:
   - non-`Data` `initialStates`
   - `lastStartTag`
3. Increment allowlists:
   - Add small, curated batches (5–20 cases) and keep them stable.

### M2 (treebuilder core)
1. Replace the placeholder stack builder with a real HTML5 treebuilder:
   - Insertion modes: initial → before html → before head → in head → after head → in body (+ the minimal “after body” modes).
   - Stack of open elements + active formatting elements (start with the subset needed by allowlisted tests).
   - Void elements + implied end tags (enables basic `p`, `br`, etc.).
2. Add a CLI mode for tree construction tests:
   - `parse` and `parse-fragment`, returning `to-test-format` output.
   - Include the parse error **count** in the transport output (html5lib tree tests only require the right count).
3. Expand allowlists:
   - Start with cases that only require: implied `<html>/<head>/<body>`, void elements, and basic in-body rules.

### M3 (foreign content + templates)
1. Namespace-sensitive element creation:
   - HTML/SVG/Math transitions (integration points first; correctness incrementally).
2. Template support:
   - Template element + separate content node in the DOM arena.
   - Template insertion modes stack.
3. Expand allowlists from `foreign-*` and `template.dat` fixtures.

### M4 (errors + locations)
1. Thread a shared error sink through tokenizer + treebuilder:
   - Record `(line,col)` as 1-based for both phases.
   - Ensure “missing doctype” and common structural errors count correctly.
2. Once counts are stable, consider mapping to canonical error code strings.

### M5 (encoding + byte input)
1. Add an internal byte-input layer + decoding to `string`.
2. Implement enough encoding sniffing/overrides for the included encoding fixtures.
3. Decide the public `parse-bytes` API once Koka’s bytes/story is locked in.

### M6 (scale up coverage)
1. Automation:
   - A script to trial-enable new cases and record which ones pass.
2. CI enforcement:
   - Require allowlist diff to be non-decreasing and tests to be green.
3. Regular maintenance:
   - Keep commits small; each commit message includes `html5lib_allowlists_cli.py diff-prev`.

## Current Status (2025-12-28)

- M0: implemented (smoke test + minimal modules).
- Tokenizer: fully allowlisted (6810/6810 = 100.0%) (includes non-`Data` `initialStates` + `lastStartTag`, spec-like rawtext/RCDATA/script end-tag recognition, better `</...` edge cases (missing end tag name, bogus-comment fallback, and EOF in end-tag-open), duplicate-attribute dropping (keeps first value), and a fuller comment state machine (including markup-declaration edge cases like `<`, `<!`, `<!--` at EOF, and correct EOF handling for comment end sequences); plus harness support for html5lib tokenizer fixtures with `doubleEscaped: true`, improved DOCTYPE JSON output (`null` when name missing), preserving U+0000 in character tokens for html5lib’s expectations (while still replacing it in comment data), and doctype error counting that emits both legacy + modern errors to match tree-construction fixtures; plus numeric character-reference errors (legacy + modern) needed by many tree fixtures.
- Tree construction: insertion-mode builder with wrapper synthesis (auto `<html>/<head>/<body>`), table/frameset/template slices, foster parenting, and a growing set of error-count behaviors to match html5lib; fragment parsing now reuses the same insertion-mode engine with synthetic `<html>` + context wrappers and post-cleanup, plus table-context fragment handling (ignore stray leading `<table>`/`</table>` in a `"table"` fragment), foreign-content namespace transitions (Math↔SVG) and integration-point handling (incl. HTML inside SVG `<foreignObject>`), foreign-content “breakout” handling (e.g. `<nobr>` in SVG/Math contexts), fragment EOF error counting (while ignoring synthetic context wrappers), and better integration-point handling for stray start tags like `<head>`; allowlists currently `1048/1590` (doc) and `101/192` (frag).
- Tree construction: insertion-mode builder with wrapper synthesis (auto `<html>/<head>/<body>`), table/frameset/template slices, foster parenting, and a growing set of error-count behaviors to match html5lib; fragment parsing now reuses the same insertion-mode engine with synthetic `<html>` + context wrappers and post-cleanup, plus table-context fragment handling (ignore stray leading `<table>`/`</table>` in a `"table"` fragment), foreign-content namespace transitions (Math↔SVG) and integration-point handling (incl. HTML inside SVG `<foreignObject>`), foreign-content “breakout” handling (e.g. `<nobr>` in SVG/Math contexts), foreign-content CDATA parsing (`<![CDATA[...]]>`) in SVG/Math contexts, namespace-sensitive table cell closing (HTML `</td>` vs SVG `<td>`), foster-parenting character error-counting, fragment EOF error counting (while ignoring synthetic context wrappers), and better integration-point handling for stray start tags like `<head>`; allowlists currently `1078/1590` (doc) and `101/192` (frag).
- Encoding: HTML5 encoding sniffing implemented and passing `html5lib-tests/encoding` (Milestone 5); decoding is still intentionally minimal (current Koka `decode-html` primarily targets sniffing correctness, not full multi-encoding text decoding).
- Treebuilder error counting: treat “non-HTML5” doctypes (non-`<!doctype html>` / with public+system ids / `forceQuirks`) as parse errors to better match html5lib’s `unknown-doctype` bucket.
- Tree-doc allowlist is now `1078/1590` (`doctype01.dat` is `30/37`, `ruby.dat` is `17/21`, `tests19.dat` is `77/103`, `tests2.dat` is `41/63`, `tests7.dat` is `22/33`, `tests10.dat` is `32/54`, `tests12.dat` is `2/2`, `tests18.dat` is `23/36`, `tests20.dat` is `52/64`, `tests9.dat` is `19/27`, `tests21.dat` is `23/23`, `namespace-sensitivity.dat` is `1/1`, `domjs-unsafe.dat` is `29/49`, `webkit01.dat` is `39/54`, `webkit02.dat` is `25/45`, `template.dat` is `63/111`, and `plain-text-unsafe.dat` is `9/33`) driven by continued incremental fixes + auto-allowlisting.
- Tree-frag allowlist is now `101/192` (notably `foreign-fragment.dat` `49/66`, `math.dat` `8/8`, `svg.dat` `8/8`, `tests4.dat` `8/9`, `tests6.dat` `5/13`, `tests_innerHTML_1.dat` `20/81`, and `template.dat` `1/1`).
- Not implemented yet (high-level): full HTML5 treebuilder insertion modes + table modes + adoption agency edge cases (especially involving table foster parenting), foreign content/templates beyond the current slice, and treebuilder error locations/codes.
 - Not implemented yet (Milestone 4 specifics): treebuilder parse error *codes* and 1-based *locations* (today the harness only validates counts, and the user-facing `ParseError` values for treebuilder are still placeholders).
- CI: runs smoke + html5lib allowlisted tests, and blocks allowlist regressions via `diff-prev --fail-on-decrease`.

# Koka notes (practical, repo-focused)

## Files, modules, and names
- File path maps to module name: `src/html5/dom.kk` → `module html5/dom`.
- Refer to definitions with a slash-qualified name: `html5/parse`, `dom/node`, `vector/list/vector`.
- `import foo/bar` brings a module into scope; aliasing like `import ... as ...` is not supported (use qualified names instead).
- Avoid using common words as identifiers (can confuse the parser), e.g. prefer `indent-prefix` over `prefix`.

## Data types
- Algebraic data types use braces (not `=`):
  - `type tok { Start(name: string) End(name: string) }`
- Product types:
  - `struct dom(nodes: vector<node>, root: nodeid)`
- Constructors are value-level functions with the same name:
  - `Dom(nodes, rootId)`, `Start("html")`, `Document(children, "no-quirks")`

## Effects (what trips you up)
- Effects are part of the function type:
  - `pub fun main() : console ()`
  - `fun f(x:int) : <exn> int`
- Some operations introduce effects:
  - Indexing a `vector` can raise bounds exceptions → typically `<exn>`.
  - Local mutation (`var`, `:=`) introduces a local effect (often inferred).
- If you hit “effects do not match”, either:
  - Add the needed effect row to the function signature (e.g. `<exn>`, `<div,exn>`), or
  - Remove/avoid the effect-causing operation.

## Control flow and loops
- `while` is a function, not syntax:
  - `while(fn() predicate, fn() action)`
- Prefer simple explicit recursion over higher-order helpers when effects get in the way.

## Strings, chars, lists, vectors (handy ops)
- Strings:
  - `trim(s)` trims whitespace.
  - `s.repeat(n)` repeats a string `n` times.
  - For string length use `chars/count(s)` (not `s.length`).
  - Convert between representations:
    - `string/vector(s) : vector<char>`
    - `string/listchar/string(cs : list<char>) : string`
- Lists:
  - `concat(xss : list<list<a>>) : list<a>`
  - `xs.map(fn(x){ ... })`, `xs.foreach(fn(x){ ... })`
- Vectors:
  - `vector(n, default)` allocates.
  - `vector/list/vector(xs)` converts `list<a> -> vector<a>`
  - `v[i]` indexes (may raise `<exn>`).

## Dot chaining
- `e.f(a,b)` desugars to `f(e,a,b)`; great for pipes without introducing a separate operator.


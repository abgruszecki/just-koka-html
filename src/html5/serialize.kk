module html5/serialize

import std/core/string
import html5/dom

fun indent-prefix(depth: int) : string
  "| " ++ ("  ".repeat(depth))

fun ns-prefix(ns: namespace) : string
  match ns
    Html -> ""
    Svg -> "svg "
    Math -> "math "

fun attr-ns-prefix(ns: attrnamespace) : string
  match ns
    None -> ""
    XLink -> "xlink "
    Xml -> "xml "
    Xmlns -> "xmlns "

fun attr-display-name(a: attr) : string
  attr-ns-prefix(a.name.ns) ++ a.name.local

fun insert-attr(a: attr, xs: list<attr>) : list<attr>
  match xs
    Nil -> Cons(a, Nil)
    Cons(b, rest) ->
      if attr-display-name(a) <= attr-display-name(b) then
        Cons(a, xs)
      else
        Cons(b, insert-attr(a, rest))

fun sort-attrs(attrs: list<attr>) : list<attr>
  // html5lib-tests sorts by the attribute name string (UTF-16 code units).
  // Koka `string` compare is fine for our current ASCII-heavy allowlists.
  match attrs
    Nil -> Nil
    Cons(a, rest) -> insert-attr(a, sort-attrs(rest))

fun render-attrs(attrs: list<attr>, depth: int) : <div,exn> list<string>
  val pad = indent-prefix(depth + 1)
  sort-attrs(attrs).map(fn(a){
    pad ++ attr-display-name(a) ++ "=\"" ++ a.value ++ "\""
  })

fun render-doctype(dt: doctype) : string
  val name = dt.name
  val has-ids = dt.public-id != Nothing || dt.system-id != Nothing
  if has-ids then
    {
      val publicId =
        match dt.public-id
          Nothing -> ""
          Just(x) -> x
      val sys =
        match dt.system-id
          Nothing -> ""
          Just(x) -> x
      "| <!DOCTYPE " ++ name ++ " \"" ++ publicId ++ "\" \"" ++ sys ++ "\">"
    }
  else if name == "" then
    "| <!DOCTYPE >"
  else
    "| <!DOCTYPE " ++ name ++ ">"

fun render-node(d: dom, id: nodeid, depth: int) : <div,exn> list<string>
  match dom/node(d,id)
    Document(children,_) ->
      concat(children.map(fn(child){ render-node(d, child, depth) }))
    DocumentFragment(children,_) ->
      concat(children.map(fn(child){ render-node(d, child, depth) }))
    Element(name,ns,attrs,children) ->
      {
        val line = indent-prefix(depth) ++ "<" ++ (ns-prefix(ns) ++ name) ++ ">"
        val attr-lines = render-attrs(attrs, depth)
        val child-lines = concat(children.map(fn(child){ render-node(d, child, depth + 1) }))
        Cons(line, attr-lines ++ child-lines)
      }
    Template(ns, attrs, children, content) ->
      {
        val line = indent-prefix(depth) ++ "<" ++ (ns-prefix(ns) ++ "template") ++ ">"
        val attr-lines = render-attrs(attrs, depth)
        val content-line = indent-prefix(depth + 1) ++ "content"
        val content-children = dom/children(d, content)
        val content-lines = concat(content-children.map(fn(child){ render-node(d, child, depth + 2) }))
        // Any direct children are treated as normal children (should be empty in practice).
        val child-lines = concat(children.map(fn(child){ render-node(d, child, depth + 1) }))
        Cons(line, attr-lines ++ Cons(content-line, content-lines) ++ child-lines)
      }
    Text(data) ->
      {
        // html5lib tree-construction fixtures are read via Python text mode, so '\r' becomes '\n'.
        // Normalize here to match the harness expectations without affecting tokenizer tests.
        val cs = string/vector(data)
        var out : list<char> := Nil
        var i := 0
        while(fn(){ i < cs.length }, fn(){
          val c = cs[i]
          out := Cons(if c == '\r' then '\n' else c, out)
          i := i + 1
        })
        val s = string/listchar/string(out.reverse)
        Cons(indent-prefix(depth) ++ "\"" ++ s ++ "\"", Nil)
      }
    Comment(data) ->
      Cons(indent-prefix(depth) ++ "<!-- " ++ data ++ " -->", Nil)
    DoctypeNode(dt) ->
      Cons(render-doctype(dt), Nil)

pub fun to-test-format(d: dom) : <div,exn> string
  render-node(d, d.root, 0).join("\n")

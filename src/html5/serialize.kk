module html5/serialize

import html5/dom

fun indent-prefix(depth: int) : string
  "| " ++ ("  ".repeat(depth))

fun render-node(d: dom, id: nodeid, depth: int) : <div,exn> list<string>
  match dom/node(d,id)
    Document(children,_) ->
      concat(children.map(fn(child){ render-node(d, child, depth) }))
    Element(name,_,_,children) ->
      Cons(indent-prefix(depth) ++ "<" ++ name ++ ">", concat(children.map(fn(child){ render-node(d, child, depth + 1) })))
    Text(data) ->
      Cons(indent-prefix(depth) ++ "\"" ++ data ++ "\"", Nil)

pub fun to-test-format(d: dom) : <div,exn> string
  render-node(d, d.root, 0).join("\n")

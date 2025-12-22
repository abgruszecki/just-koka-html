module html5

import std/core/vector
import html5/dom

pub struct parseerror(code: string, line: int, col: int)

pub struct parseoptions(
  collect-errors: bool,
  strict: bool,
  scripting-enabled: bool,
  iframe-srcdoc: bool
)

pub val default-parse-options : parseoptions =
  Parseoptions(True, False, True, False)

pub struct parseresult(dom: dom, errors: list<parseerror>)

type piece {
  Start(name: string)
  End(name: string)
  Txt(data: string)
}

fun read-until(cs: vector<char>, start: int, stop: char) : <div,exn> (text: string, end: int)
  var i := start
  var acc : list<char> := Nil
  while(fn(){
    i < cs.length && cs[i] != stop
  }, fn(){
    acc := Cons(cs[i], acc)
    i := i + 1
  })
  (string/listchar/string(acc.reverse), i)

fun tokenize-minimal(html: string) : <div,exn> list<piece>
  val cs = string/vector(html)
  fun go(i: int) : <div,exn> list<piece>
    if (i >= cs.length) then Nil else
      if (cs[i] == '<') then
        if (i + 1 < cs.length && cs[i+1] == '/') then
          val (tag, j) = read-until(cs, i + 2, '>')
          val name = trim(tag)
          if (j < cs.length) then Cons(End(name), go(j + 1)) else Cons(End(name), Nil)
        else
          val (tag, j) = read-until(cs, i + 1, '>')
          val name = trim(tag)
          if (j < cs.length) then Cons(Start(name), go(j + 1)) else Cons(Start(name), Nil)
      else
        val (txt, j) = read-until(cs, i, '<')
        val rest = go(j)
        if txt == "" then rest else Cons(Txt(txt), rest)
  go(0)

type tree {
  TEl(name: string, children: list<tree>)
  TText(data: string)
}

struct frame(name: string, children: list<tree>)

fun parse-tree(pieces: list<piece>) : list<tree>
  fun add-child(fr: frame, child: tree) : frame
    Frame(fr.name, Cons(child, fr.children))

  fun close(fr: frame) : tree
    TEl(fr.name, fr.children.reverse)

  var stack : list<frame> := Cons(Frame("#document", Nil), Nil)

  fun push(name: string)
    stack := Cons(Frame(name, Nil), stack)

  fun append(child: tree)
    match stack
      Nil -> ()
      Cons(fr, rest) -> stack := Cons(add-child(fr, child), rest)

  fun pop(endName: string)
    match stack
      Cons(top, Cons(parent, rest)) ->
        if top.name == endName then
          stack := Cons(add-child(parent, close(top)), rest)
        else
          // M0 assumes well-formed input; ignore mismatches.
          stack := Cons(add-child(parent, close(top)), rest)
      _ -> ()

  fun consume(ps: list<piece>)
    match ps
      Nil -> ()
      Cons(p, rest) ->
        match p
          Start(name) -> push(name)
          End(name) -> pop(name)
          Txt(data) -> append(TText(data))
        consume(rest)

  consume(pieces)

  match stack
    Cons(doc, _) -> doc.children.reverse
    Nil -> Nil

fun arena-from-tree(children: list<tree>) : <div> dom
  var nodesRev : list<node> := Nil
  var nextId : int := 0

  fun alloc(n: node)
    val id = nextId
    nextId := nextId + 1
    nodesRev := Cons(n, nodesRev)
    id

  fun alloc-tree(t: tree)
    match t
      TText(data) -> alloc(Text(data))
      TEl(name, kids) ->
        val childIds = kids.map(alloc-tree)
        alloc(Element(name, Html, Nil, childIds))

  val childIds = children.map(alloc-tree)
  val rootId = alloc(Document(childIds, "no-quirks"))
  val nodes = vector/list/vector(nodesRev.reverse)
  Dom(nodes, rootId)

pub fun parse(html: string, opts: parseoptions = default-parse-options) : <div,exn> parseresult
  val pieces = tokenize-minimal(html)
  val tree = parse-tree(pieces)
  Parseresult(arena-from-tree(tree), Nil)

pub fun to-test-format(d: dom) : <div,exn> string
  fun indent-prefix(depth: int) : string
    "| " ++ ("  ".repeat(depth))

  fun render(id: nodeid, depth: int) : <div,exn> list<string>
    match dom/node(d,id)
      Document(children,_) ->
        concat(children.map(fn(child){ render(child, depth) }))
      Element(name,_,_,children) ->
        Cons(indent-prefix(depth) ++ "<" ++ name ++ ">", concat(children.map(fn(child){ render(child, depth + 1) })))
      Text(data) ->
        Cons(indent-prefix(depth) ++ "\"" ++ data ++ "\"", Nil)

  render(d.root, 0).join("\n")

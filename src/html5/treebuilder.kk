module html5/treebuilder

import std/core/vector
import html5/dom
import html5/tokenizer

type tnode {
  TEl(name: string, ns: namespace, attrs: list<attr>, children: list<tnode>)
  TText(data: string)
  TComment(data: string)
  TDoctype(dt: doctype)
}

type fkind {
  FDoc
  FFrag(frag-ctx: maybe<fragmentcontext>)
  FEl(name: string, ns: namespace, attrs: list<attr>)
}

struct frame(kind: fkind, children: list<tnode>)

fun close-frame(fr: frame) : tnode
  match fr.kind
    FEl(name,ns,attrs) -> TEl(name, ns, attrs, fr.children.reverse)
    _ -> TEl("#invalid", Html, Nil, fr.children.reverse)

fun is-void-element(name: string) : bool
  match name
    "area" -> True
    "base" -> True
    "br" -> True
    "col" -> True
    "embed" -> True
    "hr" -> True
    "img" -> True
    "input" -> True
    "link" -> True
    "meta" -> True
    "param" -> True
    "source" -> True
    "track" -> True
    "wbr" -> True
    _ -> False

fun arena-from-children(rootNode: node, children: list<tnode>) : <div> dom
  var nodesRev : list<node> := Nil
  var nextId : int := 0

  fun alloc(n: node)
    val id = nextId
    nextId := nextId + 1
    nodesRev := Cons(n, nodesRev)
    id

  fun alloc-tree(t: tnode)
    match t
      TText(data) -> alloc(Text(data))
      TComment(data) -> alloc(Comment(data))
      TDoctype(dt) -> alloc(DoctypeNode(dt))
      TEl(name, ns, attrs, kids) ->
        val childIds = kids.map(alloc-tree)
        alloc(Element(name, ns, attrs, childIds))

  val childIds = children.map(alloc-tree)
  val rootId =
    match rootNode
      Document(_, quirks) -> alloc(Document(childIds, quirks))
      DocumentFragment(_, fragCtx) -> alloc(DocumentFragment(childIds, fragCtx))
      _ -> alloc(rootNode)
  val nodes = vector/list/vector(nodesRev.reverse)
  Dom(nodes, rootId)

fun build-tree(tokens: list<token>, initial: frame) : <div> list<tnode>
  fun add-child(fr: frame, child: tnode) : frame
    Frame(fr.kind, Cons(child, fr.children))

  var stack : list<frame> := Cons(initial, Nil)

  fun push(kind: fkind)
    stack := Cons(Frame(kind, Nil), stack)

  fun append(child: tnode)
    match stack
      Nil -> ()
      Cons(fr, rest) -> stack := Cons(add-child(fr, child), rest)

  fun pop(endName: string)
    fun pop-loop()
      match stack
        Cons(top, Cons(parent, rest)) ->
          match top.kind
            FEl(name,_,_) ->
              {
                stack := Cons(add-child(parent, close-frame(top)), rest)
                if name == endName then () else pop-loop()
              }
            _ -> ()
        _ -> ()
    pop-loop()

  fun has-open(tag: string)
    fun go(xs: list<frame>) : bool
      match xs
        Nil -> False
        Cons(fr, rest) ->
          match fr.kind
            FEl(name,_,_) -> if name == tag then True else go(rest)
            _ -> go(rest)
    go(stack)

  fun consume(ts: list<token>)
    match ts
      Nil -> ()
      Cons(t, rest) ->
        match t
          TokStartTag(name, attrs, selfClosing) ->
            if selfClosing || is-void-element(name) then
              append(TEl(name, Html, attrs, Nil))
            else if name == "p" && has-open("p") then
              { pop("p"); push(FEl(name, Html, attrs)) }
            else
              push(FEl(name, Html, attrs))
          TokEndTag(name) -> pop(name)
          TokCharacter(data) -> if data == "" then () else append(TText(data))
          TokComment(data) -> append(TComment(data))
          TokDoctype(name, publicId, systemId, forceQuirks) ->
            append(TDoctype(Doctype(name, publicId, systemId, forceQuirks)))
          TokEOF -> ()
        consume(rest)

  consume(tokens)

  // Close any remaining open elements.
  fun has-unclosed()
    match stack
      Cons(_, Cons(_, _)) -> True
      _ -> False

  while(has-unclosed, fn(){
    match stack
      Cons(top, Cons(parent, rest)) ->
        stack := Cons(add-child(parent, close-frame(top)), rest)
      _ -> ()
  })

  match stack
    Cons(root, _) -> root.children.reverse
    _ -> Nil

pub fun build-document(tokens: list<token>) : <div> dom
  // Minimal M2 slice:
  // - If input includes explicit <html>/<head>/<body> tags, build directly from tokens.
  // - Otherwise, synthesize <html><head><body> and put all content in <body>.
  fun has-wrapper-tag(ts: list<token>) : bool
    match ts
      Nil -> False
      Cons(t, rest) ->
        match t
          TokStartTag(name,_,_) ->
            if (name == "html" || name == "head" || name == "body") then True else has-wrapper-tag(rest)
          _ -> has-wrapper-tag(rest)

  if has-wrapper-tag(tokens) then
    {
      val initial = Frame(FDoc, Nil)
      val children = build-tree(tokens, initial)
      arena-from-children(Document(Nil, "no-quirks"), children)
    }
  else
    {
      val bodyInitial = Frame(FEl("body", Html, Nil), Nil)
      val bodyChildren = build-tree(tokens, bodyInitial)
      val body = TEl("body", Html, Nil, bodyChildren)
      val head = TEl("head", Html, Nil, Nil)
      val html = TEl("html", Html, Nil, [head, body])
      arena-from-children(Document(Nil, "no-quirks"), [html])
    }

pub fun build-fragment(tokens: list<token>, fragCtx: fragmentcontext) : <div> dom
  val initial = Frame(FFrag(Just(fragCtx)), Nil)
  val children = build-tree(tokens, initial)
  arena-from-children(DocumentFragment(Nil, Just(fragCtx)), children)

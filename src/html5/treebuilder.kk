module html5/treebuilder

import std/core/vector
import std/core/string
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

type mode {
  Initial
  BeforeHtml
  BeforeHead
  InHead
  AfterHead
  InBody
  AfterBody
}

struct frame(kind: fkind, children: list<tnode>)

struct dstate(
  stack: list<frame>,
  imode: mode,
  html-inserted: bool,
  head-inserted: bool,
  body-inserted: bool,
  errors: int
)

fun close-frame(fr: frame) : tnode
  match fr.kind
    FEl(name,ns,attrs) -> TEl(name, ns, attrs, fr.children.reverse)
    _ -> TEl("#invalid", Html, Nil, fr.children.reverse)

fun is-void-element(name: string) : bool
  match name
    "area" -> True
    "base" -> True
    "basefont" -> True
    "bgsound" -> True
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

pub fun build-document(tokens: list<token>) : <div,exn> (dom, int)
  // M2: a minimal insertion-mode document builder.
  // Goal: reliably synthesize <html><head><body> even when wrappers are missing or partial.

  fun add-child(fr: frame, child: tnode) : frame
    Frame(fr.kind, Cons(child, fr.children))

  fun st( stack: list<frame>, imode: mode, html: bool, head: bool, body: bool, errors: int ) : dstate
    Dstate(stack, imode, html, head, body, errors)

  fun append(st0: dstate, child: tnode) : dstate
    match st0.stack
      Nil -> st0
      Cons(fr, rest) ->
        st(Cons(add-child(fr, child), rest), st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors)

  fun push-el(st0: dstate, name: string, ns: namespace, attrs: list<attr>) : dstate
    st(Cons(Frame(FEl(name, ns, attrs), Nil), st0.stack), st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors)

  fun has-open(stack0: list<frame>, name: string) : <div> bool
    match stack0
      Nil -> False
      Cons(fr, rest) ->
        match fr.kind
          FEl(elname,_,_) -> if elname == name then True else has-open(rest, name)
          _ -> has-open(rest, name)

  fun pop-to(stack0: list<frame>, name: string) : <div> list<frame>
    match stack0
      Cons(top, Cons(parent, rest)) ->
        match top.kind
          FEl(elname,_,_) ->
            {
              val stack1 = Cons(add-child(parent, close-frame(top)), rest)
              if elname == name then stack1 else pop-to(stack1, name)
            }
          _ -> stack0
      _ -> stack0

  fun ensure-html(st0: dstate, attrs: list<attr>) : dstate
    if st0.html-inserted then st0 else
      {
        val st1 = push-el(st0, "html", Html, attrs)
        st(st1.stack, st1.imode, True, st1.head-inserted, st1.body-inserted, st1.errors)
      }

  fun ensure-head(st0: dstate, attrs: list<attr>) : dstate
    val st1 = ensure-html(st0, Nil)
    if st1.head-inserted then st1 else
      {
        val st2 = push-el(st1, "head", Html, attrs)
        st(st2.stack, st2.imode, st2.html-inserted, True, st2.body-inserted, st2.errors)
      }

  fun ensure-body(st0: dstate, attrs: list<attr>) : dstate
    val st1 = ensure-html(st0, Nil)
    if st1.body-inserted then st1 else
      {
        val st2 = push-el(st1, "body", Html, attrs)
        st(st2.stack, st2.imode, st2.html-inserted, st2.head-inserted, True, st2.errors)
      }

  fun insert-void(st0: dstate, name: string, attrs: list<attr>) : dstate
    append(st0, TEl(name, Html, attrs, Nil))

  fun start-tag(st0: dstate, name: string, attrs: list<attr>, selfClosing: bool) : <div> dstate
    if selfClosing || is-void-element(name) then
      insert-void(st0, name, attrs)
    else if name == "p" && has-open(st0.stack, "p") then
      {
        val stack1 = pop-to(st0.stack, "p")
        push-el(st(stack1, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors), name, Html, attrs)
      }
    else
      push-el(st0, name, Html, attrs)

  fun end-tag(st0: dstate, name: string) : <div> dstate
    if has-open(st0.stack, name) then
      st(pop-to(st0.stack, name), st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors)
    else st0

  fun is-eof-allowed(name: string) : bool
    match name
      "dd" -> True
      "dt" -> True
      "li" -> True
      "optgroup" -> True
      "option" -> True
      "p" -> True
      "rb" -> True
      "rp" -> True
      "rt" -> True
      "rtc" -> True
      "tbody" -> True
      "td" -> True
      "tfoot" -> True
      "th" -> True
      "thead" -> True
      "tr" -> True
      "body" -> True
      "html" -> True
      _ -> False

  fun has-eof-disallowed(stack0: list<frame>) : <div> bool
    match stack0
      Nil -> False
      Cons(fr, rest) ->
        match fr.kind
          FEl(name,_,_) ->
            if is-eof-allowed(name) then has-eof-disallowed(rest) else True
          _ -> has-eof-disallowed(rest)

  fun add-eof-error(st0: dstate) : <div> dstate
    if has-eof-disallowed(st0.stack) then
      st(st0.stack, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors + 1)
    else
      st0

  fun closes-p-on-start(name: string) : bool
    match name
      "address" -> True
      "article" -> True
      "aside" -> True
      "blockquote" -> True
      "center" -> True
      "details" -> True
      "dialog" -> True
      "dir" -> True
      "div" -> True
      "dl" -> True
      "fieldset" -> True
      "figcaption" -> True
      "figure" -> True
      "footer" -> True
      "header" -> True
      "hgroup" -> True
      "main" -> True
      "menu" -> True
      "nav" -> True
      "ol" -> True
      "p" -> True
      "section" -> True
      "summary" -> True
      "ul" -> True
      "pre" -> True
      "listing" -> True
      "form" -> True
      "hr" -> True
      "h1" -> True
      "h2" -> True
      "h3" -> True
      "h4" -> True
      "h5" -> True
      "h6" -> True
      _ -> False

  fun close-p-if-needed(st0: dstate, name: string) : <div> dstate
    if closes-p-on-start(name) && has-open(st0.stack, "p") then
      st(pop-to(st0.stack, "p"), st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors)
    else
      st0

  fun is-ws(s: string) : <div,exn> bool
    val cs = string/vector(s)
    var ok := True
    var i := 0
    while(fn(){ ok && i < cs.length }, fn(){
      val c = cs[i]
      ok := (c == ' ' || c == '\n' || c == '\t' || c == '\r' || c == '\u000c')
      i := i + 1
    })
    ok

  fun process-one(t: token, st0: dstate) : <div,exn> (next: dstate, reprocess: bool)
    match st0.imode
      Initial ->
        match t
          TokDoctype(name, publicId, systemId, forceQuirks) ->
            (append(st(st0.stack, BeforeHtml, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors),
                    TDoctype(Doctype(name, publicId, systemId, forceQuirks))), False)
          TokComment(data) -> (append(st0, TComment(data)), False)
          TokCharacter(s) ->
            if is-ws(s) then (st0, False) else (st(st0.stack, BeforeHtml, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors), True)
          TokEOF ->
            (st(st0.stack, BeforeHtml, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors), False)
          _ ->
            (st(st0.stack, BeforeHtml, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors), True)
      BeforeHtml ->
        match t
          TokComment(data) -> (append(st0, TComment(data)), False)
          TokCharacter(s) ->
            if is-ws(s) then (st0, False)
            else { val st1 = ensure-html(st0, Nil); (st(st1.stack, BeforeHead, True, st1.head-inserted, st1.body-inserted, st1.errors), True) }
          TokStartTag(name, attrs, _) ->
            if name == "html" then
              { val st1 = ensure-html(st0, attrs); (st(st1.stack, BeforeHead, True, st1.head-inserted, st1.body-inserted, st1.errors), False) }
            else
              { val st1 = ensure-html(st0, Nil); (st(st1.stack, BeforeHead, True, st1.head-inserted, st1.body-inserted, st1.errors), True) }
          TokEndTag(_) ->
            { val st1 = ensure-html(st0, Nil); (st(st1.stack, BeforeHead, True, st1.head-inserted, st1.body-inserted, st1.errors), True) }
          TokEOF ->
            { val st1 = ensure-html(st0, Nil); (st(st1.stack, BeforeHead, True, st1.head-inserted, st1.body-inserted, st1.errors), True) }
          TokDoctype(_,_,_,_) ->
            (st0, False)
      BeforeHead ->
        match t
          TokComment(data) -> (append(st0, TComment(data)), False)
          TokCharacter(s) ->
            if is-ws(s) then (st0, False)
            else
              { val st1 = ensure-head(st0, Nil); (st(st1.stack, InHead, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True) }
          TokStartTag(name, attrs, _) ->
            if name == "head" then
              { val st1 = ensure-head(st0, attrs); (st(st1.stack, InHead, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False) }
            elif name == "html" then
              { val st1 = ensure-html(st0, attrs); (st(st1.stack, BeforeHead, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False) }
            else
              { val st1 = ensure-head(st0, Nil); (st(st1.stack, InHead, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True) }
          TokEndTag(_) ->
            { val st1 = ensure-head(st0, Nil); (st(st1.stack, InHead, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True) }
          TokEOF ->
            { val st1 = ensure-head(st0, Nil); (st(st1.stack, InHead, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True) }
          TokDoctype(_,_,_,_) ->
            (st0, False)
      InHead ->
        match t
          TokEndTag(name) ->
            if name == "head" then
              { val stack1 = pop-to(st0.stack, "head"); (st(stack1, AfterHead, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors), False) }
            else (end-tag(st0, name), False)
          TokStartTag(name, attrs, _selfClosing) ->
            if name == "html" then (st0, False)
            elif name == "head" then (st0, False)
            elif name == "body" then
              {
                val stack1 = pop-to(st0.stack, "head")
                val st1 = ensure-body(st(stack1, InBody, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors), attrs)
                (st(st1.stack, InBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False)
              }
            elif name == "base" || name == "basefont" || name == "bgsound" || name == "link" || name == "meta" then
              (insert-void(st0, name, attrs), False)
            else
              { val stack1 = pop-to(st0.stack, "head"); (st(stack1, AfterHead, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors), True) }
          TokCharacter(s) ->
            if is-ws(s) then
              (append(st0, TText(s)), False)
            else
              { val stack1 = pop-to(st0.stack, "head"); (st(stack1, AfterHead, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors), True) }
          TokComment(data) -> (append(st0, TComment(data)), False)
          TokDoctype(_,_,_,_) -> (st0, False)
          TokEOF ->
            { val stack1 = pop-to(st0.stack, "head"); (st(stack1, AfterHead, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors), True) }
      AfterHead ->
        match t
          TokComment(data) -> (append(st0, TComment(data)), False)
          TokCharacter(_) ->
            { val st1 = ensure-body(st0, Nil); (st(st1.stack, InBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True) }
          TokStartTag(name, attrs, _) ->
            if name == "body" then
              { val st1 = ensure-body(st0, attrs); (st(st1.stack, InBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False) }
            else
              { val st1 = ensure-body(st0, Nil); (st(st1.stack, InBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True) }
          TokEndTag(_) ->
            { val st1 = ensure-body(st0, Nil); (st(st1.stack, InBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True) }
          TokDoctype(_,_,_,_) -> (st0, False)
          TokEOF ->
            { val st1 = ensure-body(st0, Nil); (st(st1.stack, InBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True) }
      InBody ->
        match t
          TokStartTag(name, attrs, selfClosing) ->
            if name == "html" || name == "head" || name == "body" then (st0, False)
            else { val st1 = close-p-if-needed(st0, name); (start-tag(st1, name, attrs, selfClosing), False) }
          TokEndTag(name) ->
            if name == "body" then
              { val st1 = end-tag(st0, "body"); (st(st1.stack, AfterBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False) }
            elif name == "html" then (st0, False)
            else (end-tag(st0, name), False)
          TokCharacter(s) ->
            if s == "" then (st0, False) else (append(st0, TText(s)), False)
          TokComment(data) -> (append(st0, TComment(data)), False)
          TokDoctype(_,_,_,_) -> (st0, False)
          TokEOF -> (add-eof-error(st0), False)
      AfterBody ->
        match t
          TokComment(data) -> (append(st0, TComment(data)), False)
          TokCharacter(s) ->
            if is-ws(s) then (st0, False) else (st(st0.stack, InBody, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors), True)
          TokEOF -> (st0, False)
          _ -> (st(st0.stack, InBody, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors), True)

  fun process(ts: list<token>, st0: dstate) : <div,exn> dstate
    match ts
      Nil -> st0
      Cons(t, rest) ->
        {
          val (next, reprocess) = process-one(t, st0)
          if reprocess then process(Cons(t, rest), next) else process(rest, next)
        }

  val st0 = st(Cons(Frame(FDoc, Nil), Nil), Initial, False, False, False, 0)
  val st1 = process(tokens, st0)
  val st2 = if st1.html-inserted then st1 else ensure-html(st1, Nil)
  val st3 =
    if st2.head-inserted then st2
    else
      { val stx = ensure-head(st2, Nil); st(pop-to(stx.stack, "head"), stx.imode, stx.html-inserted, stx.head-inserted, stx.body-inserted, stx.errors) }
  val st4 =
    if st3.body-inserted then st3
    else
      { val stx = ensure-body(st3, Nil); st(pop-to(stx.stack, "body"), stx.imode, stx.html-inserted, stx.head-inserted, stx.body-inserted, stx.errors) }

  fun close-all(stack0: list<frame>) : <div> list<frame>
    match stack0
      Cons(top, Cons(parent, rest)) ->
        close-all(Cons(add-child(parent, close-frame(top)), rest))
      _ -> stack0

  val closed =
    match close-all(st4.stack)
      Cons(root, _) -> root.children.reverse
      _ -> Nil
  val dom = arena-from-children(Document(Nil, "no-quirks"), closed)
  (dom, st4.errors)

pub fun build-fragment(tokens: list<token>, fragCtx: fragmentcontext) : <div> dom
  val initial = Frame(FFrag(Just(fragCtx)), Nil)
  val children = build-tree(tokens, initial)
  arena-from-children(DocumentFragment(Nil, Just(fragCtx)), children)

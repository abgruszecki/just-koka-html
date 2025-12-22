module html5/treebuilder

import std/core/vector
import std/core/string
import html5/dom
import html5/tokenizer

type tnode {
  TEl(name: string, ns: namespace, attrs: list<attr>, children: list<tnode>)
  TTemplate(ns: namespace, attrs: list<attr>, content: list<tnode>)
  TText(data: string)
  TComment(data: string)
  TDoctype(dt: doctype)
}

type fkind {
  FDoc
  FFrag(frag-ctx: maybe<fragmentcontext>)
  FEl(name: string, ns: namespace, attrs: list<attr>)
  FTemplateContent
}

type mode {
  Initial
  BeforeHtml
  BeforeHead
  InHead
  AfterHead
  InBody
  InTable
  InTableBody
  InColumnGroup
  InRow
  InCell
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

fun lower-ascii(c: char) : char
  if (c >= 'A' && c <= 'Z') then (c.int + 32).char else c

fun lower-ascii-string(s: string) : <div,exn> string
  val cs = string/vector(s)
  fun go(i: int, acc: list<char>) : <div,exn> list<char>
    if i >= cs.length then acc.reverse
    else go(i + 1, Cons(lower-ascii(cs[i]), acc))
  string/listchar/string(go(0, Nil))

fun slice-string(cs: vector<char>, start: int, end: int) : <div,exn> string
  // end is exclusive
  var acc : list<char> := Nil
  var i := start
  while(fn(){ i < end && i < cs.length }, fn(){
    acc := Cons(cs[i], acc)
    i := i + 1
  })
  string/listchar/string(acc.reverse)

fun map-attr-name(name: string) : <div,exn> attrname
  // Only enough for html5lib tree dump prefixing (xlink/xml/xmlns).
  val cs = string/vector(name)
  var colon := -1
  var i := 0
  while(fn(){ colon < 0 && i < cs.length }, fn(){
    if cs[i] == ':' then colon := i else ()
    i := i + 1
  })
  if colon < 0 then
    if name == "xmlns" then Attrname(Xmlns, "xmlns") else Attrname(None, name)
  else
    {
      val pre = slice-string(cs, 0, colon)
      val local = slice-string(cs, colon + 1, cs.length)
      match pre
        "xlink" -> Attrname(XLink, local)
        "xml" -> Attrname(Xml, local)
        "xmlns" -> Attrname(Xmlns, local)
        _ -> Attrname(None, name)
    }

fun map-attrs(attrs: list<attr>) : <div,exn> list<attr>
  attrs.map(fn(a){ Attr(map-attr-name(a.name.local), a.value) })

fun svg-tag-adjust(name: string) : string
  // https://html.spec.whatwg.org/multipage/parsing.html#svg-tag-name-adjustments
  match name
    "altglyph" -> "altGlyph"
    "altglyphdef" -> "altGlyphDef"
    "altglyphitem" -> "altGlyphItem"
    "animatecolor" -> "animateColor"
    "animatemotion" -> "animateMotion"
    "animatetransform" -> "animateTransform"
    "clippath" -> "clipPath"
    "feblend" -> "feBlend"
    "fecolormatrix" -> "feColorMatrix"
    "fecomponenttransfer" -> "feComponentTransfer"
    "fecomposite" -> "feComposite"
    "feconvolvematrix" -> "feConvolveMatrix"
    "fediffuselighting" -> "feDiffuseLighting"
    "fedisplacementmap" -> "feDisplacementMap"
    "fedistantlight" -> "feDistantLight"
    "fedropshadow" -> "feDropShadow"
    "feflood" -> "feFlood"
    "fefunca" -> "feFuncA"
    "fefuncb" -> "feFuncB"
    "fefuncg" -> "feFuncG"
    "fefuncr" -> "feFuncR"
    "fegaussianblur" -> "feGaussianBlur"
    "feimage" -> "feImage"
    "femerge" -> "feMerge"
    "femergenode" -> "feMergeNode"
    "femorphology" -> "feMorphology"
    "feoffset" -> "feOffset"
    "fepointlight" -> "fePointLight"
    "fespecularlighting" -> "feSpecularLighting"
    "fespotlight" -> "feSpotLight"
    "fetile" -> "feTile"
    "feturbulence" -> "feTurbulence"
    "foreignobject" -> "foreignObject"
    "glyphref" -> "glyphRef"
    "lineargradient" -> "linearGradient"
    "radialgradient" -> "radialGradient"
    "textpath" -> "textPath"
    _ -> name

fun is-math-text-integration-point(name: string) : bool
  match name
    "mi" -> True
    "mo" -> True
    "mn" -> True
    "ms" -> True
    "mtext" -> True
    _ -> False

fun is-svg-html-integration-point(name: string) : bool
  // https://html.spec.whatwg.org/multipage/parsing.html#html-integration-point
  name == "foreignObject" || name == "desc" || name == "title"

fun current-element(stack0: list<frame>) : <div> (name: string, ns: namespace)
  match stack0
    Nil -> ("", Html)
    Cons(fr, rest) ->
      match fr.kind
        FEl(name, ns, _) -> (name, ns)
        FFrag(mctx) ->
          match mctx
            Just(Fragmentcontext(tag, ns)) -> (tag, ns)
            _ -> current-element(rest)
        _ -> current-element(rest)

fun element-ns(stack0: list<frame>, name: string) : <div> namespace
  val (parentName, parentNs) = current-element(stack0)
  match parentNs
    Html ->
      if name == "svg" then Svg
      elif name == "math" then Math
      else Html
    Svg ->
      if is-svg-html-integration-point(parentName) then Html else Svg
    Math ->
      if is-math-text-integration-point(parentName) then Html else Math

fun adjust-tag-name(ns: namespace, name: string) : string
  match ns
    Svg -> svg-tag-adjust(name)
    _ -> name

fun is-html-ns(ns: namespace) : bool
  match ns
    Html -> True
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
      TTemplate(ns, attrs, contentKids) ->
        {
          val contentChildIds = contentKids.map(alloc-tree)
          val contentId = alloc(DocumentFragment(contentChildIds, Nothing))
          alloc(Template(ns, attrs, Nil, contentId))
        }

  val childIds = children.map(alloc-tree)
  val rootId =
    match rootNode
      Document(_, quirks) -> alloc(Document(childIds, quirks))
      DocumentFragment(_, fragCtx) -> alloc(DocumentFragment(childIds, fragCtx))
      _ -> alloc(rootNode)
  val nodes = vector/list/vector(nodesRev.reverse)
  Dom(nodes, rootId)

fun build-tree(tokens: list<token>, initial: frame) : <div,exn> list<tnode>
  fun add-child(fr: frame, child: tnode) : frame
    Frame(fr.kind, Cons(child, fr.children))

  var stack : list<frame> := Cons(initial, Nil)

  fun push(kind: fkind)
    stack := Cons(Frame(kind, Nil), stack)

  fun append(child: tnode)
    match stack
      Nil -> ()
      Cons(fr, rest) -> stack := Cons(add-child(fr, child), rest)

  fun pop-ci(endName: string)
    val want = lower-ascii-string(endName)
    fun pop-loop()
      match stack
        Cons(top, Cons(parent, rest)) ->
          match top.kind
            FEl(name,_,_) ->
              {
                stack := Cons(add-child(parent, close-frame(top)), rest)
                if lower-ascii-string(name) == want then () else pop-loop()
              }
            _ -> ()
        _ -> ()
    pop-loop()

  fun pop-template()
    // Close any open elements inside the template content, then synthesize the template node.
    fun close-until-content()
      match stack
        Cons(top, Cons(parent, rest)) ->
          match top.kind
            FEl(_,_,_) ->
              { stack := Cons(add-child(parent, close-frame(top)), rest); close-until-content() }
            _ -> ()
        _ -> ()

    close-until-content()
    match stack
      Cons(contentFr, Cons(tplFr, Cons(parent, rest))) ->
        match (contentFr.kind, tplFr.kind)
          (FTemplateContent, FEl(name, ns, attrs)) ->
            if lower-ascii-string(name) == "template" then
              {
                val node = TTemplate(ns, attrs, contentFr.children.reverse)
                stack := Cons(add-child(parent, node), rest)
              }
            else ()
          _ -> ()
      _ -> ()

  fun has-open(xs: list<frame>, tag: string) : <div,exn> bool
    val want = lower-ascii-string(tag)
    fun go(ys: list<frame>) : <div,exn> bool
      match ys
        Nil -> False
        Cons(fr, rest) ->
          match fr.kind
            FEl(name,_,_) -> if lower-ascii-string(name) == want then True else go(rest)
            _ -> go(rest)
    go(xs)

  fun consume(ts: list<token>)
    match ts
      Nil -> ()
      Cons(t, rest) ->
        match t
          TokStartTag(name, attrs, selfClosing) ->
            {
              val ns0 = element-ns(stack, name)
              val ns = ns0
              val adjName0 = adjust-tag-name(ns, name)
              val adjName = adjName0
              val attrs1 = map-attrs(attrs)
              if (is-html-ns(ns) && adjName == "template" && !selfClosing) then
                { push(FEl("template", Html, attrs1)); push(FTemplateContent) }
              elif selfClosing || (is-html-ns(ns) && is-void-element(adjName)) then
                append(TEl(adjName, ns, attrs1, Nil))
              else if (is-html-ns(ns) && adjName == "p" && has-open(stack, "p")) then
                { pop-ci("p"); push(FEl(adjName, ns, attrs1)) }
              else
                push(FEl(adjName, ns, attrs1))
            }
          TokEndTag(name) ->
            if lower-ascii-string(name) == "template" then pop-template() else pop-ci(name)
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
      Cons(contentFr, Cons(tplFr, Cons(parent, rest))) ->
        match (contentFr.kind, tplFr.kind)
          (FTemplateContent, FEl(name, ns, attrs)) ->
            if lower-ascii-string(name) == "template" then
              stack := Cons(add-child(parent, TTemplate(ns, attrs, contentFr.children.reverse)), rest)
            else
              stack := Cons(add-child(tplFr, close-frame(contentFr)), Cons(parent, rest))
          _ ->
            match stack
              Cons(top, Cons(parent2, rest2)) ->
                stack := Cons(add-child(parent2, close-frame(top)), rest2)
              _ -> ()
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

  fun has-open(stack0: list<frame>, name: string) : <div,exn> bool
    match stack0
      Nil -> False
      Cons(fr, rest) ->
        match fr.kind
          FEl(elname,_,_) -> if lower-ascii-string(elname) == lower-ascii-string(name) then True else has-open(rest, name)
          _ -> has-open(rest, name)

  fun pop-to(stack0: list<frame>, name: string) : <div,exn> list<frame>
    match stack0
      Cons(top, Cons(parent, rest)) ->
        match top.kind
          FEl(elname,_,_) ->
            {
              val stack1 = Cons(add-child(parent, close-frame(top)), rest)
              if lower-ascii-string(elname) == lower-ascii-string(name) then stack1 else pop-to(stack1, name)
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

  fun insert-void(st0: dstate, name: string, ns: namespace, attrs: list<attr>) : dstate
    append(st0, TEl(name, ns, attrs, Nil))

  fun pop-template-stack(stack0: list<frame>) : <div,exn> list<frame>
    fun close-inside(stack1: list<frame>) : <div,exn> list<frame>
      match stack1
        Cons(top, Cons(parent, rest)) ->
          match top.kind
            FEl(_,_,_) -> close-inside(Cons(add-child(parent, close-frame(top)), rest))
            _ -> stack1
        _ -> stack1

    val stack1 = close-inside(stack0)
    match stack1
      Cons(contentFr, Cons(tplFr, Cons(parent, rest))) ->
        match (contentFr.kind, tplFr.kind)
          (FTemplateContent, FEl(name, ns, attrs)) ->
            if lower-ascii-string(name) == "template" then
              Cons(add-child(parent, TTemplate(ns, attrs, contentFr.children.reverse)), rest)
            else stack1
          _ -> stack1
      _ -> stack1

  fun start-tag(st0: dstate, rawName: string, attrs: list<attr>, selfClosing: bool) : <div,exn> dstate
    {
      val ns0 = element-ns(st0.stack, rawName)
      val ns = ns0
      val name = adjust-tag-name(ns, rawName)
      val attrs1 = map-attrs(attrs)
      if (is-html-ns(ns) && name == "template" && !selfClosing) then
        {
          val st1 = push-el(st0, "template", Html, attrs1)
          st(Cons(Frame(FTemplateContent, Nil), st1.stack), st1.imode, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors)
        }
      elif selfClosing || (is-html-ns(ns) && is-void-element(name)) then
        insert-void(st0, name, ns, attrs1)
      else if (is-html-ns(ns) && name == "p" && has-open(st0.stack, "p")) then
        {
          val stack1 = pop-to(st0.stack, "p")
          push-el(st(stack1, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors), name, ns, attrs1)
        }
      else
        push-el(st0, name, ns, attrs1)
    }

  fun end-tag(st0: dstate, name: string) : <div,exn> dstate
    if lower-ascii-string(name) == "template" then
      st(pop-template-stack(st0.stack), st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors)
    elif has-open(st0.stack, name) then
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

  fun close-p-if-needed(st0: dstate, name: string) : <div,exn> dstate
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

  fun add-error(st0: dstate) : dstate
    st(st0.stack, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors + 1)

  fun is-one-of(name: string, xs: list<string>) : <div,exn> bool
    match xs
      Nil -> False
      Cons(x, rest) -> if lower-ascii-string(name) == lower-ascii-string(x) then True else is-one-of(name, rest)

  fun is-table-section(name: string) : bool
    name == "tbody" || name == "thead" || name == "tfoot"

  fun is-table-cell(name: string) : bool
    name == "td" || name == "th"

  fun has-open-any(stack0: list<frame>, tags: list<string>) : <div,exn> bool
    match tags
      Nil -> False
      Cons(t, rest) -> if has-open(stack0, t) then True else has-open-any(stack0, rest)

  fun close-cell(st0: dstate) : <div,exn> dstate
    if has-open(st0.stack, "td") then
      st(pop-to(st0.stack, "td"), st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors)
    elif has-open(st0.stack, "th") then
      st(pop-to(st0.stack, "th"), st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors)
    else
      st0

  fun close-row(st0: dstate) : <div,exn> dstate
    if has-open(st0.stack, "tr") then
      st(pop-to(st0.stack, "tr"), st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors)
    else
      st0

  fun ensure-tbody(st0: dstate) : <div,exn> dstate
    if has-open-any(st0.stack, Cons("tbody", Cons("thead", Cons("tfoot", Nil)))) then
      st0
    else
      push-el(st0, "tbody", Html, Nil)

  fun ensure-tr(st0: dstate) : <div,exn> dstate
    if has-open(st0.stack, "tr") then st0 else push-el(st0, "tr", Html, Nil)

  fun foster-stack(stack0: list<frame>, child: tnode) : <div,exn> maybe<list<frame>>
    match stack0
      Cons(top, Cons(parent, rest)) ->
        match top.kind
          FEl(name,_,_) ->
            if lower-ascii-string(name) == "table" then
              Just(Cons(top, Cons(add-child(parent, child), rest)))
            else
              match foster-stack(Cons(parent, rest), child)
                Just(tail) -> Just(Cons(top, tail))
                Nothing -> Nothing
          _ ->
            match foster-stack(Cons(parent, rest), child)
              Just(tail) -> Just(Cons(top, tail))
              Nothing -> Nothing
      _ -> Nothing

  fun foster-append(st0: dstate, child: tnode) : <div,exn> dstate
    match foster-stack(st0.stack, child)
      Just(stack1) -> st(stack1, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors)
      Nothing -> append(st0, child)

  fun in-template-content(stack0: list<frame>) : bool
    match stack0
      Nil -> False
      Cons(fr, rest) ->
        match fr.kind
          FTemplateContent -> True
          _ -> in-template-content(rest)

  fun foster-needed(stack0: list<frame>) : <div,exn> bool
    val (nm, _) = current-element(stack0)
    val name = lower-ascii-string(nm)
    name == "table" || name == "tbody" || name == "thead" || name == "tfoot" || name == "tr"

  fun mode-from-stack(stack0: list<frame>) : <div,exn> mode
    if has-open(stack0, "td") || has-open(stack0, "th") then InCell
    elif has-open(stack0, "tr") then InRow
    elif has-open-any(stack0, Cons("tbody", Cons("thead", Cons("tfoot", Nil)))) then InTableBody
    elif has-open(stack0, "colgroup") then InColumnGroup
    elif has-open(stack0, "table") then InTable
    else InBody

  fun with-mode(st0: dstate, m: mode) : dstate
    st(st0.stack, m, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors)

  fun update-mode(st0: dstate) : <div,exn> dstate
    with-mode(st0, mode-from-stack(st0.stack))

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
          TokStartTag(name, attrs, selfClosing) ->
            if name == "html" then (st0, False)
            elif name == "head" then (st0, False)
            elif name == "body" then
              {
                val stack1 = pop-to(st0.stack, "head")
                val st1 = ensure-body(st(stack1, InBody, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors), attrs)
                (st(st1.stack, InBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False)
              }
            elif name == "base" || name == "basefont" || name == "bgsound" || name == "link" || name == "meta" then
              (start-tag(st0, name, attrs, selfClosing), False)
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
            else
              {
                val ns = element-ns(st0.stack, name)
                val adj = adjust-tag-name(ns, name)
                val st1 = if is-html-ns(ns) then close-p-if-needed(st0, adj) else st0
                val st2 = start-tag(st1, name, attrs, selfClosing)
                if is-html-ns(ns) && adj == "table" && !selfClosing then
                  (st(st2.stack, InTable, st2.html-inserted, st2.head-inserted, st2.body-inserted, st2.errors), False)
                else
                  (st2, False)
              }
          TokEndTag(name) ->
            if name == "body" then
              { val st1 = end-tag(st0, "body"); (st(st1.stack, AfterBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False) }
            elif name == "html" then (st0, False)
            else
              if has-open(st0.stack, name) then
                (end-tag(st0, name), False)
              else
                // Treat stray end tags as parse errors (html5lib tree tests count these).
                (st(st0.stack, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors + 1), False)
          TokCharacter(s) ->
            if s == "" then (st0, False) else (append(st0, TText(s)), False)
          TokComment(data) -> (append(st0, TComment(data)), False)
          TokDoctype(_,_,_,_) -> (st0, False)
          TokEOF -> (add-eof-error(st0), False)
      InTable ->
        match t
          TokStartTag(name, attrs, selfClosing) ->
            if in-template-content(st0.stack) then
              (start-tag(st0, name, attrs, selfClosing), False)
            elif name == "table" then (add-error(st0), False)
            elif name == "colgroup" then
              { val st1 = start-tag(st0, name, attrs, selfClosing); (st(st1.stack, InColumnGroup, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False) }
            elif is-table-section(name) then
              { val st1 = start-tag(st0, name, attrs, selfClosing); (st(st1.stack, InTableBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False) }
            elif name == "tr" then
              {
                val st1 = add-error(st0)
                val st2 = ensure-tbody(st1)
                val st3 = start-tag(st(st2.stack, InTableBody, st2.html-inserted, st2.head-inserted, st2.body-inserted, st2.errors), name, attrs, selfClosing)
                (st(st3.stack, InRow, st3.html-inserted, st3.head-inserted, st3.body-inserted, st3.errors), False)
              }
            elif is-table-cell(name) then
              {
                val st1 = add-error(st0)
                val st2 = ensure-tbody(st1)
                val st3 = ensure-tr(st2)
                val st4 = start-tag(st(st3.stack, InRow, st3.html-inserted, st3.head-inserted, st3.body-inserted, st3.errors), name, attrs, selfClosing)
                (st(st4.stack, InCell, st4.html-inserted, st4.head-inserted, st4.body-inserted, st4.errors), False)
              }
            else
              (start-tag(st0, name, attrs, selfClosing), False)
          TokEndTag(name) ->
            if in-template-content(st0.stack) then
              if has-open(st0.stack, name) then
                { val st1 = end-tag(st0, name); (update-mode(st1), False) }
              else
                (st(st0.stack, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors + 1), False)
            elif name == "table" then
              { val st1 = end-tag(st0, "table"); (st(st1.stack, InBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False) }
            else
              if has-open(st0.stack, name) then
                { val st1 = end-tag(st0, name); (update-mode(st1), False) }
              else
                (st(st0.stack, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors + 1), False)
          TokCharacter(s) ->
            if is-ws(s) || in-template-content(st0.stack) || !foster-needed(st0.stack) then
              (append(st0, TText(s)), False)
            else
              (foster-append(st0, TText(s)), False)
          TokComment(data) -> (append(st0, TComment(data)), False)
          TokDoctype(_,_,_,_) -> (add-error(st0), False)
          TokEOF -> (add-eof-error(st0), False)
      InTableBody ->
        match t
          TokStartTag(name, attrs, selfClosing) ->
            if in-template-content(st0.stack) then
              (start-tag(st0, name, attrs, selfClosing), False)
            elif name == "tr" then
              { val st1 = start-tag(st0, name, attrs, selfClosing); (st(st1.stack, InRow, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False) }
            elif is-table-cell(name) then
              {
                val st1 = add-error(st0)
                val st2 = ensure-tr(st1)
                val st3 = start-tag(st(st2.stack, InRow, st2.html-inserted, st2.head-inserted, st2.body-inserted, st2.errors), name, attrs, selfClosing)
                (st(st3.stack, InCell, st3.html-inserted, st3.head-inserted, st3.body-inserted, st3.errors), False)
              }
            elif is-table-section(name) then
              {
                val st1 = close-row(st0)
                val st2 = end-tag(st1, name)
                (st(st2.stack, InTable, st2.html-inserted, st2.head-inserted, st2.body-inserted, st2.errors), True)
              }
            elif name == "table" then
              { val st1 = add-error(st0); (st(st1.stack, InTable, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True) }
            else
              (start-tag(st0, name, attrs, selfClosing), False)
          TokEndTag(name) ->
            if in-template-content(st0.stack) then
              if has-open(st0.stack, name) then
                { val st1 = end-tag(st0, name); (update-mode(st1), False) }
              else
                (st(st0.stack, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors + 1), False)
            elif is-table-section(name) then
              if has-open(st0.stack, name) then
                { val st1 = end-tag(st0, name); (st(st1.stack, InTable, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False) }
              else
                (st(st0.stack, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors + 1), False)
            elif name == "table" then
              { val st1 = close-row(st0); val st2 = end-tag(st1, "tbody"); (st(st2.stack, InTable, st2.html-inserted, st2.head-inserted, st2.body-inserted, st2.errors), True) }
            else
              if has-open(st0.stack, name) then
                { val st1 = end-tag(st0, name); (update-mode(st1), False) }
              else
                (st(st0.stack, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors + 1), False)
          TokCharacter(s) ->
            if is-ws(s) || in-template-content(st0.stack) || !foster-needed(st0.stack) then
              (append(st0, TText(s)), False)
            else
              (foster-append(st0, TText(s)), False)
          TokComment(data) -> (append(st0, TComment(data)), False)
          TokDoctype(_,_,_,_) -> (add-error(st0), False)
          TokEOF -> (add-eof-error(st0), False)
      InColumnGroup ->
        match t
          TokStartTag(name, attrs, selfClosing) ->
            if in-template-content(st0.stack) then
              (start-tag(st0, name, attrs, selfClosing), False)
            elif name == "col" then
              (start-tag(st0, name, attrs, selfClosing), False)
            elif name == "template" then
              (start-tag(st0, name, attrs, selfClosing), False)
            else
              { val st1 = add-error(st0); val st2 = end-tag(st1, "colgroup"); (st(st2.stack, InTable, st2.html-inserted, st2.head-inserted, st2.body-inserted, st2.errors), True) }
          TokEndTag(name) ->
            if in-template-content(st0.stack) then
              if has-open(st0.stack, name) then
                { val st1 = end-tag(st0, name); (update-mode(st1), False) }
              else
                (st(st0.stack, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors + 1), False)
            elif name == "colgroup" then
              { val st1 = end-tag(st0, "colgroup"); (st(st1.stack, InTable, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False) }
            elif name == "table" then
              { val st1 = end-tag(st0, "colgroup"); (st(st1.stack, InTable, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True) }
            else
              if has-open(st0.stack, name) then
                { val st1 = end-tag(st0, name); (update-mode(st1), False) }
              else
                (st(st0.stack, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors + 1), False)
          TokCharacter(s) ->
            if is-ws(s) then (append(st0, TText(s)), False) else (add-error(st0), False)
          TokComment(data) -> (append(st0, TComment(data)), False)
          TokDoctype(_,_,_,_) -> (add-error(st0), False)
          TokEOF -> (add-eof-error(st0), False)
      InRow ->
        match t
          TokStartTag(name, attrs, selfClosing) ->
            if in-template-content(st0.stack) then
              (start-tag(st0, name, attrs, selfClosing), False)
            elif is-table-cell(name) then
              { val st1 = start-tag(st0, name, attrs, selfClosing); (st(st1.stack, InCell, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False) }
            elif name == "tr" then
              { val st1 = add-error(st0); (st(st1.stack, InTableBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True) }
            elif is-table-section(name) || name == "table" then
              { val st1 = add-error(st0); (st(st1.stack, InTableBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True) }
            else
              (start-tag(st0, name, attrs, selfClosing), False)
          TokEndTag(name) ->
            if in-template-content(st0.stack) then
              if has-open(st0.stack, name) then
                { val st1 = end-tag(st0, name); (update-mode(st1), False) }
              else
                (st(st0.stack, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors + 1), False)
            elif name == "tr" then
              { val st1 = end-tag(st0, "tr"); (st(st1.stack, InTableBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False) }
            elif name == "table" then
              { val st1 = end-tag(st0, "tr"); (st(st1.stack, InTableBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True) }
            else
              if has-open(st0.stack, name) then
                { val st1 = end-tag(st0, name); (update-mode(st1), False) }
              else
                (st(st0.stack, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors + 1), False)
          TokCharacter(s) ->
            if is-ws(s) || in-template-content(st0.stack) || !foster-needed(st0.stack) then
              (append(st0, TText(s)), False)
            else
              (foster-append(st0, TText(s)), False)
          TokComment(data) -> (append(st0, TComment(data)), False)
          TokDoctype(_,_,_,_) -> (add-error(st0), False)
          TokEOF -> (add-eof-error(st0), False)
      InCell ->
        match t
          TokEndTag(name) ->
            if in-template-content(st0.stack) then
              if has-open(st0.stack, name) then
                { val st1 = end-tag(st0, name); (update-mode(st1), False) }
              else
                (st(st0.stack, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors + 1), False)
            elif is-table-cell(name) then
              { val st1 = end-tag(st0, name); (st(st1.stack, InRow, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False) }
            elif name == "table" then
              { val st1 = close-cell(st0); (st(st1.stack, InRow, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True) }
            else
              if has-open(st0.stack, name) then
                { val st1 = end-tag(st0, name); (update-mode(st1), False) }
              else
                (st(st0.stack, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors + 1), False)
          TokStartTag(name, attrs, selfClosing) ->
            if in-template-content(st0.stack) then
              (start-tag(st0, name, attrs, selfClosing), False)
            elif is-one-of(name, Cons("td", Cons("th", Cons("tr", Cons("tbody", Cons("thead", Cons("tfoot", Cons("table", Nil)))))))) then
              { val st1 = close-cell(st0); (st(st1.stack, InRow, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True) }
            else
              (start-tag(st0, name, attrs, selfClosing), False)
          TokCharacter(s) ->
            if s == "" then (st0, False) else (append(st0, TText(s)), False)
          TokComment(data) -> (append(st0, TComment(data)), False)
          TokDoctype(_,_,_,_) -> (add-error(st0), False)
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

  fun close-all(stack0: list<frame>) : <div,exn> list<frame>
    match stack0
      Cons(contentFr, Cons(tplFr, Cons(parent, rest))) ->
        match (contentFr.kind, tplFr.kind)
          (FTemplateContent, FEl(name, ns, attrs)) ->
            if lower-ascii-string(name) == "template" then
              close-all(Cons(add-child(parent, TTemplate(ns, attrs, contentFr.children.reverse)), rest))
            else
              close-all(Cons(add-child(tplFr, close-frame(contentFr)), Cons(parent, rest)))
          _ ->
            match stack0
              Cons(top, Cons(parent2, rest2)) ->
                close-all(Cons(add-child(parent2, close-frame(top)), rest2))
              _ -> stack0
      Cons(top, Cons(parent, rest)) ->
        close-all(Cons(add-child(parent, close-frame(top)), rest))
      _ -> stack0

  val closed =
    match close-all(st4.stack)
      Cons(root, _) -> root.children.reverse
      _ -> Nil
  val dom = arena-from-children(Document(Nil, "no-quirks"), closed)
  (dom, st4.errors)

pub fun build-fragment(tokens: list<token>, fragCtx: fragmentcontext) : <div,exn> dom
  val initial = Frame(FFrag(Just(fragCtx)), Nil)
  val children = build-tree(tokens, initial)
  arena-from-children(DocumentFragment(Nil, Just(fragCtx)), children)

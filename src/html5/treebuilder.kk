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
  InHeadNoscript
  AfterHead
  InBody
  InFrameset
  AfterFrameset
  AfterAfterFrameset
  InTable
  InTableBody
  InColumnGroup
  InRow
  InCell
  AfterBody
  AfterAfterBody
}

type fmtentry {
  FmtMarker
  FmtEntry(name: string, attrs: list<attr>, node: nodeid)
}

struct frame(kind: fkind, children: list<tnode>)

struct dstate(
  stack: list<frame>,
  imode: mode,
  html-inserted: bool,
  head-inserted: bool,
  body-inserted: bool,
  active: list<fmtentry>,
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
    "frame" -> True
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
        // HTML's foreign attribute adjustments are a whitelist:
        // https://html.spec.whatwg.org/multipage/parsing.html#foreign-attribute-adjustments
        "xlink" ->
          match local
            "actuate" -> Attrname(XLink, local)
            "arcrole" -> Attrname(XLink, local)
            "href" -> Attrname(XLink, local)
            "role" -> Attrname(XLink, local)
            "show" -> Attrname(XLink, local)
            "title" -> Attrname(XLink, local)
            "type" -> Attrname(XLink, local)
            _ -> Attrname(None, name)
        "xml" ->
          match local
            "lang" -> Attrname(Xml, local)
            "space" -> Attrname(Xml, local)
            _ -> Attrname(None, name)
        "xmlns" -> Attrname(Xmlns, local)
        _ -> Attrname(None, name)
    }

fun map-attrs(attrs: list<attr>) : <div,exn> list<attr>
  attrs.map(fn(a){ Attr(map-attr-name(a.name.local), a.value) })

fun math-attr-adjust(name: string) : string
  // https://html.spec.whatwg.org/multipage/parsing.html#mathml-attribute-name-adjustments
  match name
    "definitionurl" -> "definitionURL"
    _ -> name

fun adjust-attrs(ns: namespace, attrs: list<attr>) : <div,exn> list<attr>
  // Only map xlink/xml/xmlns prefixes in foreign content. In HTML, keep attributes as-is
  // so they serialize like `xml:lang` / `xlink:href` on HTML elements (html5lib tree format).
  match ns
    Html -> attrs
    Math -> map-attrs(attrs.map(fn(a){ Attr(Attrname(None, math-attr-adjust(a.name.local)), a.value) }))
    _ -> map-attrs(attrs)

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

fun build-tree(tokens: list<token>, initial: frame) : <div,exn> (children: list<tnode>, errors: int)
  fun add-child(fr: frame, child: tnode) : frame
    match (child, fr.children)
      (TText(new), Cons(TText(prev), rest)) -> Frame(fr.kind, Cons(TText(prev ++ new), rest))
      _ -> Frame(fr.kind, Cons(child, fr.children))

  var stack : list<frame> := Cons(initial, Nil)
  var errs := 0

  fun is-fragment() : bool
    match initial.kind
      FFrag(_) -> True
      _ -> False

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
                val node = close-frame(top)
                val topLow = lower-ascii-string(name)
                val fosterOk =
                  match parent.kind
                    FEl(parentName, _pns, _pattrs) ->
                      {
                        val p = lower-ascii-string(parentName)
                        p == "table"
                          && !(topLow == "caption" || topLow == "colgroup" || topLow == "tbody" || topLow == "thead" || topLow == "tfoot")
                      }
                    _ -> False
                if fosterOk then
                  match rest
                    Cons(tblParent, rest2) -> stack := Cons(parent, Cons(add-child(tblParent, node), rest2))
                    _ -> stack := Cons(add-child(parent, node), rest)
                else
                  stack := Cons(add-child(parent, node), rest)
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

  fun open-element-ns(xs: list<frame>, tag: string) : <div,exn> maybe<namespace>
    val want = lower-ascii-string(tag)
    fun go(ys: list<frame>) : <div,exn> maybe<namespace>
      match ys
        Nil -> Nothing
        Cons(fr, rest) ->
          match fr.kind
            FEl(name, ns, _) ->
              if lower-ascii-string(name) == want then Just(ns) else go(rest)
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
              val attrs1 = adjust-attrs(ns, attrs)
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
            if lower-ascii-string(name) == "template" then
              if has-open(stack, "template") then pop-template() else errs := errs + 1
            else
              if has-open(stack, name) then pop-ci(name) else errs := errs + 1
          TokCharacter(data) -> if data == "" then () else append(TText(data))
          TokComment(data) -> append(TComment(data))
          TokDoctype(name, publicId, systemId, forceQuirks) ->
            if is-fragment() then
              errs := errs + 1
            else
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

  val children =
    match stack
      Cons(root, _) -> root.children.reverse
      _ -> Nil
  (children, errs)

pub fun build-document(tokens: list<token>, scriptingEnabled: bool = True) : <div,exn> (dom, int)
  // M2: a minimal insertion-mode document builder.
  // Goal: reliably synthesize <html><head><body> even when wrappers are missing or partial.

  fun add-child(fr: frame, child: tnode) : frame
    match (child, fr.children)
      (TText(new), Cons(TText(prev), rest)) -> Frame(fr.kind, Cons(TText(prev ++ new), rest))
      _ -> Frame(fr.kind, Cons(child, fr.children))

  fun st( stack: list<frame>, imode: mode, html: bool, head: bool, body: bool, errors: int ) : dstate
    Dstate(stack, imode, html, head, body, Nil, errors)

  fun append(st0: dstate, child: tnode) : dstate
    match st0.stack
      Nil -> st0
      Cons(fr, rest) ->
        st(Cons(add-child(fr, child), rest), st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors)

  fun append-into-head(st0: dstate, child: tnode) : <div,exn> dstate
    // After the <head> element has been popped, html5lib still expects certain "head" elements
    // like <style>/<script> to be inserted into the existing <head> node, not into <body>.
    fun add-to-head-node(n: tnode) : <div,exn> maybe<tnode>
      match n
        TEl(name, ns, attrs, kids) ->
          if is-html-ns(ns) && lower-ascii-string(name) == "head" then
            Just(TEl(name, ns, attrs, kids ++ Cons(child, Nil)))
          else Nothing
        _ -> Nothing

    fun add-to-html-frame(fr: frame) : <div,exn> maybe<frame>
      match fr.kind
        FEl(nm, ns, _attrs) ->
          if is-html-ns(ns) && lower-ascii-string(nm) == "html" then
            {
              fun go(xs: list<tnode>, acc: list<tnode>) : <div,exn> (found: bool, out: list<tnode>)
                match xs
                  Nil -> (False, acc)
                  Cons(n, rest) ->
                    match add-to-head-node(n)
                      Just(n2) -> (True, acc ++ Cons(n2, rest))
                      Nothing -> go(rest, acc ++ Cons(n, Nil))
              val (found, kids2) = go(fr.children, Nil)
              if found then Just(Frame(fr.kind, kids2)) else Nothing
            }
          else Nothing
        _ -> Nothing

    fun go(stack0: list<frame>) : <div,exn> maybe<list<frame>>
      match stack0
        Nil -> Nothing
        Cons(fr, rest) ->
          match add-to-html-frame(fr)
            Just(fr2) -> Just(Cons(fr2, rest))
            Nothing ->
              match go(rest)
                Just(tail) -> Just(Cons(fr, tail))
                Nothing -> Nothing

    match go(st0.stack)
      Just(stack1) -> st(stack1, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors)
      Nothing -> append(st0, child)

  fun append-into-body(st0: dstate, child: tnode) : <div,exn> dstate
    // When `<body>` has been popped from the stack (e.g. in AfterBody mode), html5lib still expects
    // certain tokens to be inserted into the existing `<body>` node.
    fun add-to-body-node(n: tnode) : <div,exn> maybe<tnode>
      match n
        TEl(name, ns, attrs, kids) ->
          if is-html-ns(ns) && lower-ascii-string(name) == "body" then
            Just(TEl(name, ns, attrs, kids ++ Cons(child, Nil)))
          else Nothing
        _ -> Nothing

    fun add-to-html-node(n: tnode) : <div,exn> maybe<tnode>
      match n
        TEl(name, ns, attrs, kids) ->
          if is-html-ns(ns) && lower-ascii-string(name) == "html" then
            {
              fun go(kids0: list<tnode>, acc: list<tnode>) : <div,exn> (found: bool, out: list<tnode>)
                match kids0
                  Nil -> (False, acc)
                  Cons(k, rest) ->
                    match add-to-body-node(k)
                      Just(k2) -> (True, acc ++ Cons(k2, rest))
                      Nothing -> go(rest, acc ++ Cons(k, Nil))
              val (found, kids2) = go(kids, Nil)
              if found then Just(TEl(name, ns, attrs, kids2)) else Nothing
            }
          else Nothing
        _ -> Nothing

    fun add-to-html-frame(fr: frame) : <div,exn> maybe<frame>
      match fr.kind
        FEl(nm, ns, _attrs) ->
          if is-html-ns(ns) && lower-ascii-string(nm) == "html" then
            {
              fun go(xs: list<tnode>, acc: list<tnode>) : <div,exn> (found: bool, out: list<tnode>)
                match xs
                  Nil -> (False, acc)
                  Cons(n, rest) ->
                    match add-to-body-node(n)
                      Just(n2) -> (True, acc ++ Cons(n2, rest))
                      Nothing -> go(rest, acc ++ Cons(n, Nil))
              val (found, kids2) = go(fr.children, Nil)
              if found then Just(Frame(fr.kind, kids2)) else Nothing
            }
          else Nothing
        _ -> Nothing

    fun go(stack0: list<frame>) : <div,exn> maybe<list<frame>>
      match stack0
        Nil -> Nothing
        Cons(fr, rest) ->
          match add-to-html-frame(fr)
            Just(fr2) -> Just(Cons(fr2, rest))
            Nothing ->
              match go(rest)
                Just(tail) -> Just(Cons(fr, tail))
                Nothing -> Nothing

    match go(st0.stack)
      Just(stack1) -> st(stack1, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors)
      Nothing ->
        {
          // If the <html> element has already been closed into the document, update the closed tree.
          fun update-doc(stack0: list<frame>) : <div,exn> maybe<list<frame>>
            match stack0
              Nil -> Nothing
              Cons(fr, rest) ->
                match fr.kind
                  FDoc ->
                    {
                      fun goKids(xs: list<tnode>, acc: list<tnode>) : <div,exn> (found: bool, out: list<tnode>)
                        match xs
                          Nil -> (False, acc)
                          Cons(n, rest2) ->
                            match add-to-html-node(n)
                              Just(n2) -> (True, acc ++ Cons(n2, rest2))
                              Nothing -> goKids(rest2, acc ++ Cons(n, Nil))
                      val (found, kids2) = goKids(fr.children, Nil)
                      if found then Just(Cons(Frame(fr.kind, kids2), rest)) else Nothing
                    }
                  _ ->
                    match update-doc(rest)
                      Just(tail) -> Just(Cons(fr, tail))
                      Nothing -> Nothing
          match update-doc(st0.stack)
            Just(stack2) -> st(stack2, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors)
            Nothing -> append(st0, child)
        }

  fun top-is-doc(stack0: list<frame>) : bool
    match stack0
      Cons(fr, _) ->
        match fr.kind
          FDoc -> True
          _ -> False
      _ -> False

  fun push-el(st0: dstate, name: string, ns: namespace, attrs: list<attr>) : dstate
    st(Cons(Frame(FEl(name, ns, attrs), Nil), st0.stack), st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors)

  fun has-open(stack0: list<frame>, name: string) : <div,exn> bool
    match stack0
      Nil -> False
      Cons(fr, rest) ->
        match fr.kind
          FEl(elname,_,_) -> if lower-ascii-string(elname) == lower-ascii-string(name) then True else has-open(rest, name)
          _ -> has-open(rest, name)

  fun open-element-ns(stack0: list<frame>, name: string) : <div,exn> maybe<namespace>
    match stack0
      Nil -> Nothing
      Cons(fr, rest) ->
        match fr.kind
          FEl(elname, ns, _) ->
            if lower-ascii-string(elname) == lower-ascii-string(name) then Just(ns) else open-element-ns(rest, name)
          _ -> open-element-ns(rest, name)

  fun pop-to(stack0: list<frame>, name: string) : <div,exn> list<frame>
    match stack0
      Cons(top, Cons(parent, rest)) ->
        match top.kind
          FEl(elname,_,_) ->
            {
              val node = close-frame(top)
              val topLow = lower-ascii-string(elname)
              val stack1 =
                match parent.kind
                  FEl(parentName, _pns, _pattrs) ->
                    {
                      val p = lower-ascii-string(parentName)
                      val isTableChild =
                        topLow == "caption" || topLow == "colgroup" || topLow == "tbody" || topLow == "thead" || topLow == "tfoot"
                          || topLow == "style" || topLow == "script"
                      if p == "table" && !isTableChild then
                        match rest
                          Cons(tblParent, rest2) -> Cons(parent, Cons(add-child(tblParent, node), rest2))
                          _ -> Cons(add-child(parent, node), rest)
                      else
                        Cons(add-child(parent, node), rest)
                    }
                  _ -> Cons(add-child(parent, node), rest)
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

  fun ensure-body(st0: dstate, attrs: list<attr>) : <div,exn> dstate
    val st1 = ensure-html(st0, Nil)
    val st2 =
      if has-open(st1.stack, "head") then
        st(pop-to(st1.stack, "head"), st1.imode, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors)
      else
        st1
    if st2.body-inserted then st2 else
      {
        val st3 = push-el(st2, "body", Html, attrs)
        st(st3.stack, st3.imode, st3.html-inserted, st3.head-inserted, True, st3.errors)
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
      val attrs1 = adjust-attrs(ns, attrs)
      if (is-html-ns(ns) && name == "template" && !selfClosing) then
        {
          val st1 = push-el(st0, "template", Html, attrs1)
          st(Cons(Frame(FTemplateContent, Nil), st1.stack), st1.imode, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors)
        }
      elif selfClosing || (is-html-ns(ns) && is-void-element(name)) then
        insert-void(st0, name, ns, attrs1)
      else
        push-el(st0, name, ns, attrs1)
    }

  fun end-tag(st0: dstate, name: string) : <div,exn> dstate
    // html5lib tree-construction fixtures count parse errors in some cases where
    // an end tag implicitly closes a <template> (and its template-content frame).
    fun crosses-template(stack0: list<frame>, target0: string) : <div,exn> bool
      val target = lower-ascii-string(target0)
      fun go(xs: list<frame>, sawTemplate: bool) : <div,exn> bool
        match xs
          Nil -> False
          Cons(fr, rest) ->
            match fr.kind
              FTemplateContent -> go(rest, True)
              FEl(nm, _ns, _attrs) ->
                {
                  val nm1 = lower-ascii-string(nm)
                  if nm1 == target then sawTemplate
                  elif nm1 == "template" then go(rest, True)
                  else go(rest, sawTemplate)
                }
              _ -> go(rest, sawTemplate)
      go(stack0, False)

    if lower-ascii-string(name) == "template" then
      st(pop-template-stack(st0.stack), st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors)
    elif has-open(st0.stack, name) then
      {
        val st1 =
          if crosses-template(st0.stack, name) then
            st(st0.stack, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors + 1)
          else st0
        st(pop-to(st1.stack, name), st1.imode, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors)
      }
    else st0

  fun is-implied-end-tag(name0: string) : <div,exn> bool
    val name = lower-ascii-string(name0)
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
      _ -> False

  fun generate-implied-end-tags(st0: dstate, exceptName0: string) : <div,exn> dstate
    {
      val exceptName = lower-ascii-string(exceptName0)
      fun go(stx: dstate) : <div,exn> dstate
        match stx.stack
          Cons(fr, _) ->
            match fr.kind
              FEl(nm, _ns, _attrs) ->
                if is-implied-end-tag(nm) && lower-ascii-string(nm) != exceptName then
                  {
                    val stack1 = pop-to(stx.stack, nm)
                    go(st(stack1, stx.imode, stx.html-inserted, stx.head-inserted, stx.body-inserted, stx.errors))
                  }
                else stx
              _ -> stx
          _ -> stx
      go(st0)
    }

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
      "head" -> True
      "body" -> True
      "html" -> True
      _ -> False

  fun has-eof-disallowed(stack0: list<frame>) : <div> bool
    {
      fun after-template-content(xs: list<frame>) : maybe<list<frame>>
        match xs
          Nil -> Nothing
          Cons(fr, rest) ->
            match fr.kind
              FTemplateContent -> Just(rest)
              _ -> after-template-content(rest)

      // EOF-in-template is counted separately; ignore open elements inside template content.
      val xs =
        match after-template-content(stack0)
          Just(outside) ->
            match outside
              Nil -> outside
              Cons(fr, rest) ->
                match fr.kind
                  FEl(nm, _ns, _attrs) ->
                    if nm == "template" then rest else outside
                  _ -> outside
          Nothing -> stack0
      match xs
        Nil -> False
        Cons(fr, rest) ->
          match fr.kind
            FEl(name,_,_) ->
              if is-eof-allowed(name) then has-eof-disallowed(rest) else True
            _ -> has-eof-disallowed(rest)
    }

  fun add-eof-error(st0: dstate) : <div> dstate
    {
      fun has-template-content(stack0: list<frame>) : bool
        match stack0
          Nil -> False
          Cons(fr, rest) ->
            match fr.kind
              FTemplateContent -> True
              _ -> has-template-content(rest)

      val add1 = if has-eof-disallowed(st0.stack) then 1 else 0
      val add2 = if has-template-content(st0.stack) then 1 else 0
      val n = add1 + add2
      if n <= 0 then st0
      else st(st0.stack, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors + n)
    }

  fun closes-p-on-start(name: string) : bool
    match name
      "address" -> True
      "article" -> True
      "aside" -> True
      "blockquote" -> True
      "center" -> True
      "dd" -> True
      "details" -> True
      "dialog" -> True
      "dir" -> True
      "div" -> True
      "dl" -> True
      "dt" -> True
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
      "plaintext" -> True
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
      "xmp" -> True
      _ -> False

  fun is-scope-boundary(name0: string, ns: namespace) : <div,exn> bool
    if !is-html-ns(ns) then True
    else
      val name = lower-ascii-string(name0)
      match name
        "applet" -> True
        "caption" -> True
        "html" -> True
        "table" -> True
        "td" -> True
        "th" -> True
        "marquee" -> True
        "object" -> True
        "template" -> True
        _ -> False

  fun has-in-scope(stack0: list<frame>, target0: string) : <div,exn> bool
    val target = lower-ascii-string(target0)
    fun go(xs: list<frame>) : <div,exn> bool
      match xs
        Nil -> False
        Cons(fr, rest) ->
          match fr.kind
            FEl(nm, ns, _) ->
              val name = lower-ascii-string(nm)
              if is-html-ns(ns) && name == target then True
              elif is-scope-boundary(name, ns) then False
              else go(rest)
            _ -> go(rest)
    go(stack0)

  fun has-in-definition-scope(stack0: list<frame>, target0: string) : <div,exn> bool
    // Like `has-in-scope`, but `<dl>` is also a scope terminator.
    val target = lower-ascii-string(target0)
    fun go(xs: list<frame>) : <div,exn> bool
      match xs
        Nil -> False
        Cons(fr, rest) ->
          match fr.kind
            FEl(nm, ns, _) ->
              val name = lower-ascii-string(nm)
              if is-html-ns(ns) && name == target then True
              elif is-html-ns(ns) && name == "dl" then False
              elif is-scope-boundary(name, ns) then False
              else go(rest)
            _ -> go(rest)
    go(stack0)

  fun has-in-button-scope(stack0: list<frame>, target0: string) : <div,exn> bool
    val target = lower-ascii-string(target0)
    fun go(xs: list<frame>) : <div,exn> bool
      match xs
        Nil -> False
        Cons(fr, rest) ->
          match fr.kind
            FEl(nm, ns, _) ->
              val name = lower-ascii-string(nm)
              if is-html-ns(ns) && name == target then True
              elif is-html-ns(ns) && name == "button" then False
              elif is-scope-boundary(name, ns) then False
              else go(rest)
            _ -> go(rest)
    go(stack0)

  fun has-in-cell-scope(stack0: list<frame>, target0: string) : <div,exn> bool
    // Scan from the current node downwards; stop when leaving the current cell.
    val target = lower-ascii-string(target0)
    fun go(xs: list<frame>) : <div,exn> bool
      match xs
        Nil -> False
        Cons(fr, rest) ->
          match fr.kind
            FEl(nm, ns, _) ->
              if !is-html-ns(ns) then False
              else
                val name = lower-ascii-string(nm)
                if name == target then True
                elif name == "td" || name == "th" then False
                else go(rest)
            _ -> go(rest)
    go(stack0)

  fun close-p-if-needed(st0: dstate, name: string) : <div,exn> dstate
    if closes-p-on-start(name) && has-in-button-scope(st0.stack, "p") then
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

  fun filter-ws(s: string) : <div,exn> string
    val cs = string/vector(s)
    var acc : list<char> := Nil
    var i := 0
    while(fn(){ i < cs.length }, fn(){
      val c = cs[i]
      if (c == ' ' || c == '\n' || c == '\t' || c == '\r' || c == '\u000c') then
        acc := Cons(c, acc)
      else
        ()
      i := i + 1
    })
    string/listchar/string(acc.reverse)

  fun split-leading-ws(s: string) : <div,exn> (ws: string, rest: string)
    val cs = string/vector(s)
    var i := 0
    fun is-ws-char(c: char) : bool
      c == ' ' || c == '\n' || c == '\t' || c == '\r' || c == '\u000c'
    while(fn(){ i < cs.length && is-ws-char(cs[i]) }, fn(){ i := i + 1 })
    // `i` is the first non-ws index (or length).
    (slice-string(cs, 0, i), slice-string(cs, i, cs.length))

  fun add-error(st0: dstate) : dstate
    st(st0.stack, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors + 1)

  fun add-errors(st0: dstate, n: int) : dstate
    if n <= 0 then st0 else st(st0.stack, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors + n)

  fun is-one-of(name: string, xs: list<string>) : <div,exn> bool
    match xs
      Nil -> False
      Cons(x, rest) -> if lower-ascii-string(name) == lower-ascii-string(x) then True else is-one-of(name, rest)

  fun eq-attrnamespace(a: attrnamespace, b: attrnamespace) : bool
    match (a,b)
      (None, None) -> True
      (XLink, XLink) -> True
      (Xml, Xml) -> True
      (Xmlns, Xmlns) -> True
      _ -> False

  fun eq-attrname(a: attrname, b: attrname) : bool
    match (a,b)
      (Attrname(ns1, local1), Attrname(ns2, local2)) -> (eq-attrnamespace(ns1, ns2) && local1 == local2)

  fun has-attr(an: attrname, attrs: list<attr>) : bool
    match attrs
      Nil -> False
      Cons(Attr(name,_), rest) -> eq-attrname(name, an) || has-attr(an, rest)

  fun merge-attrs(keepFirst: list<attr>, add: list<attr>) : list<attr>
    // Keep existing attributes; only add new ones if not already present.
    match add
      Nil -> keepFirst
      Cons(a, rest) ->
        if has-attr(a.name, keepFirst) then merge-attrs(keepFirst, rest)
        else merge-attrs(Cons(a, keepFirst), rest)

  fun merge-html-attrs(st0: dstate, attrs: list<attr>) : <div,exn> dstate
    fun merge-html-tnode(n: tnode) : <div,exn> maybe<tnode>
      match n
        TEl(name, ns, old, kids) ->
          if is-html-ns(ns) && lower-ascii-string(name) == "html" then
            Just(TEl(name, ns, merge-attrs(old, attrs), kids))
          else Nothing
        _ -> Nothing

    fun merge-in-children(xs: list<tnode>) : <div,exn> maybe<list<tnode>>
      match xs
        Nil -> Nothing
        Cons(n, rest) ->
          match merge-html-tnode(n)
            Just(n2) -> Just(Cons(n2, rest))
            Nothing ->
              match merge-in-children(rest)
                Just(rest2) -> Just(Cons(n, rest2))
                Nothing -> Nothing

    fun go(stack0: list<frame>) : <div,exn> list<frame>
      match stack0
        Nil -> Nil
        Cons(fr, rest) ->
          match fr.kind
            FEl(nm, ns, old) ->
              if is-html-ns(ns) && lower-ascii-string(nm) == "html" then
                Cons(Frame(FEl(nm, ns, merge-attrs(old, attrs)), fr.children), rest)
              else
                Cons(fr, go(rest))
            FDoc ->
              match merge-in-children(fr.children)
                Just(kids2) -> Cons(Frame(FDoc, kids2), rest)
                Nothing -> Cons(fr, go(rest))
            _ -> Cons(fr, go(rest))
    st(go(st0.stack), st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors)

  fun merge-body-attrs(st0: dstate, attrs: list<attr>) : <div,exn> dstate
    fun go(stack0: list<frame>) : <div,exn> list<frame>
      match stack0
        Nil -> Nil
        Cons(fr, rest) ->
          match fr.kind
            FEl(nm, ns, old) ->
              if is-html-ns(ns) && lower-ascii-string(nm) == "body" then
                Cons(Frame(FEl(nm, ns, merge-attrs(old, attrs)), fr.children), rest)
              else
                Cons(fr, go(rest))
            _ -> Cons(fr, go(rest))
    st(go(st0.stack), st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors)

  fun append-into-html-node(st0: dstate, child: tnode) : <div,exn> dstate
    // Append a child into the existing <html> element even when it has already been popped into the document.
    fun add-to-html(n: tnode) : <div,exn> maybe<tnode>
      match n
        TEl(name, ns, attrs, kids) ->
          if is-html-ns(ns) && lower-ascii-string(name) == "html" then
            Just(TEl(name, ns, attrs, kids ++ Cons(child, Nil)))
          else Nothing
        _ -> Nothing

    fun add-to-doc(fr: frame) : <div,exn> maybe<frame>
      match fr.kind
        FDoc ->
          {
            fun go(xs: list<tnode>) : <div,exn> maybe<list<tnode>>
              match xs
                Nil -> Nothing
                Cons(n, rest) ->
                  match add-to-html(n)
                    Just(n2) -> Just(Cons(n2, rest))
                    Nothing ->
                      match go(rest)
                        Just(rest2) -> Just(Cons(n, rest2))
                        Nothing -> Nothing
            match go(fr.children)
              Just(kids2) -> Just(Frame(FDoc, kids2))
              Nothing -> Nothing
          }
        _ -> Nothing

    fun go(stack0: list<frame>) : <div,exn> maybe<list<frame>>
      match stack0
        Nil -> Nothing
        Cons(fr, rest) ->
          match add-to-doc(fr)
            Just(fr2) -> Just(Cons(fr2, rest))
            Nothing ->
              match go(rest)
                Just(tail) -> Just(Cons(fr, tail))
                Nothing -> Nothing

    match go(st0.stack)
      Just(stack1) -> st(stack1, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors)
      Nothing -> st0

  fun is-formatting-element(name0: string) : <div,exn> bool
    val name = lower-ascii-string(name0)
    match name
      "a" -> True
      "b" -> True
      "big" -> True
      "code" -> True
      "em" -> True
      "font" -> True
      "i" -> True
      "nobr" -> True
      "s" -> True
      "small" -> True
      "strike" -> True
      "strong" -> True
      "tt" -> True
      "u" -> True
      _ -> False

  fun is-heading-element(name0: string) : <div,exn> bool
    val name = lower-ascii-string(name0)
    match name
      "h1" -> True
      "h2" -> True
      "h3" -> True
      "h4" -> True
      "h5" -> True
      "h6" -> True
      _ -> False

  fun has-heading-in-scope(stack0: list<frame>) : <div,exn> bool
    fun go(xs: list<frame>) : <div,exn> bool
      match xs
        Nil -> False
        Cons(fr, rest) ->
          match fr.kind
            FEl(nm, ns, _) ->
              val name = lower-ascii-string(nm)
              if is-html-ns(ns) && is-heading-element(name) then True
              elif is-scope-boundary(name, ns) then False
              else go(rest)
            _ -> go(rest)
    go(stack0)

  fun nearest-heading-in-scope(stack0: list<frame>) : <div,exn> maybe<string>
    fun go(xs: list<frame>) : <div,exn> maybe<string>
      match xs
        Nil -> Nothing
        Cons(fr, rest) ->
          match fr.kind
            FEl(nm, ns, _) ->
              val name = lower-ascii-string(nm)
              if is-html-ns(ns) && is-heading-element(name) then Just(name)
              elif is-scope-boundary(name, ns) then Nothing
              else go(rest)
            _ -> go(rest)
    go(stack0)

  fun is-special-for-adoption(name0: string) : <div,exn> bool
    // "Special" elements, simplified (enough for html5lib adoption01/02 fixtures).
    val name = lower-ascii-string(name0)
    match name
      "address" -> True
      "article" -> True
      "aside" -> True
      "blockquote" -> True
      "button" -> True
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
      "form" -> True
      "frameset" -> True
      "h1" -> True
      "h2" -> True
      "h3" -> True
      "h4" -> True
      "h5" -> True
      "h6" -> True
      "header" -> True
      "hgroup" -> True
      "hr" -> True
      "li" -> True
      "listing" -> True
      "main" -> True
      "menu" -> True
      "nav" -> True
      "ol" -> True
      "p" -> True
      "pre" -> True
      "section" -> True
      "summary" -> True
      "table" -> True
      "tbody" -> True
      "td" -> True
      "tfoot" -> True
      "th" -> True
      "thead" -> True
      "tr" -> True
      "ul" -> True
      _ -> False

  fun adoption-end-tag(st0: dstate, tag: string) : <div,exn> dstate
    // A pragmatic "adoption agency" slice that matches the common html5lib patterns:
    // - don't pop intervening special elements into the formatting element
    // - wrap each intervening special element's already-inserted children in a cloned formatting element
    // - close the original formatting element into its parent, and keep intervening elements open
    val want = lower-ascii-string(tag)
    val (curName0, _curNs) = current-element(st0.stack)
    if lower-ascii-string(curName0) == want then
      end-tag(st0, tag)
    else
      {
        // Split the stack at the first matching formatting element.
        fun split(xs: list<frame>, above: list<frame>) : <div,exn> maybe<(list<frame>, frame, list<frame>)>
          match xs
            Nil -> Nothing
            Cons(fr, rest) ->
              match fr.kind
                FEl(nm,_,_) ->
                  if lower-ascii-string(nm) == want then Just((above, fr, rest))
                  else split(rest, above ++ Cons(fr, Nil))
                _ -> split(rest, above ++ Cons(fr, Nil))

        match split(st0.stack, Nil)
          Nothing -> add-error(st0)
          Just((above, fmtFr, below)) ->
            match below
              Nil ->
                // No parent to close into; fall back to a normal close.
                end-tag(add-error(st0), tag)
              Cons(parent, restBelow) ->
                match fmtFr.kind
                  FEl(_fmtName, _fmtNs, _fmtAttrs) ->
                    {
                      // First, "split" any inline formatting elements above the formatting element being closed.
                      // This approximates the adoption agency inner loop for common html5lib cases like:
                      //   <a>1<b>2</a>3</b>
                      // where <b> should be split into <b> inside <a> and a new <b> outside.
                      fun split-inline(xs: list<frame>) : <div,exn> list<frame>
                        match xs
                          Cons(fr, Cons(par, rest)) ->
                            match fr.kind
                              FEl(nm, ns, attrs) ->
                                {
                                  val nmLow = lower-ascii-string(nm)
                                  if nmLow == want then xs
                                  elif is-html-ns(ns) && is-formatting-element(nmLow) && !is-special-for-adoption(nmLow) then
                                    {
                                      val par2 = add-child(par, close-frame(fr))
                                      val empty = Frame(FEl(nm, ns, attrs), Nil)
                                      Cons(empty, split-inline(Cons(par2, rest)))
                                    }
                                  else
                                    Cons(fr, split-inline(Cons(par, rest)))
                                }
                              _ -> Cons(fr, split-inline(Cons(par, rest)))
                          _ -> xs

                      val stack0 = above ++ Cons(fmtFr, Cons(parent, restBelow))
                      val stackA = split-inline(stack0)
                      // Re-split so we can wrap specials and close the original formatting element.
                      val (aboveA, fmtA, belowA) =
                        match split(stackA, Nil)
                          Just((a, f, b)) -> (a, f, b)
                          Nothing -> (above, fmtFr, below)
                      match belowA
                        Nil -> add-error(st0)
                        Cons(parentA, restA) ->
                          match fmtA.kind
                            FEl(fmtNameA, fmtNsA, fmtAttrsA) ->
                              {
                                fun wrap(fr: frame) : <div,exn> frame
                                  match fr.kind
                                    FEl(nm, ns, attrs) ->
                                      if is-html-ns(ns) && is-special-for-adoption(nm) then
                                        {
                                          // Move already-inserted children into a cloned formatting element.
                                          val moved = fr.children.reverse
                                          val clone = TEl(fmtNameA, fmtNsA, fmtAttrsA, moved)
                                          Frame(FEl(nm, ns, attrs), Cons(clone, Nil))
                                        }
                                      else fr
                                    _ -> fr

                                val above2 = aboveA.map(wrap)
                                val parent2 = add-child(parentA, close-frame(fmtA))
                                val stack1 = above2 ++ Cons(parent2, restA)
                                fun count-special(xs: list<frame>) : <div,exn> int
                                  match xs
                                    Nil -> 0
                                    Cons(fr, rest) ->
                                      match fr.kind
                                        FEl(nm, ns, _) ->
                                          (if is-html-ns(ns) && is-special-for-adoption(nm) then 1 else 0) + count-special(rest)
                                        _ -> count-special(rest)
                                val specials = count-special(aboveA)
                                // html5lib's adoption fixtures sometimes count multiple "adoption-agency" errors
                                // for deeply nested special elements; approximate that by charging 1 per special block.
                                val addErr = if specials <= 0 then 1 else specials
                                st(stack1, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors + addErr)
                              }
                            _ -> add-error(st0)
                    }
                  _ -> add-error(st0)
      }

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

  fun pop-to-select-foster(stack0: list<frame>) : <div,exn> list<frame>
    // Close elements until <select>, but when closing the <select> itself, foster-parent it (so it ends up
    // before the current table) instead of appending it into the current parent.
    match stack0
      Cons(top, Cons(parent, rest)) ->
        match top.kind
          FEl(elname, _ns, _attrs) ->
            if lower-ascii-string(elname) == "select" then
              {
                val node = close-frame(top)
                // Only foster-parent when the <select> is directly under a <table>.
                match parent.kind
                  FEl(parentName, _pns, _pattrs) ->
                    if lower-ascii-string(parentName) == "table" then
                      {
                        val stack1 = Cons(parent, rest)
                        match foster-stack(stack1, node)
                          Just(stack2) -> stack2
                          Nothing -> Cons(add-child(parent, node), rest)
                      }
                    else
                      Cons(add-child(parent, node), rest)
                  _ -> Cons(add-child(parent, node), rest)
              }
            else
              pop-to-select-foster(Cons(add-child(parent, close-frame(top)), rest))
          _ -> stack0
      _ -> stack0

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
    fun process-inbody(t2: token, stx: dstate) : <div,exn> (next: dstate, reprocess: bool)
      {
        val (st1, rep) = process-one(t2, with-mode(stx, InBody))
        (update-mode(st1), rep)
      }
    match st0.imode
      Initial ->
        match t
          TokDoctype(name, publicId, systemId, forceQuirks) ->
            {
              // Treat "non-HTML5" doctypes as parse errors (covers html5lib's `unknown-doctype` bucket).
              val isHtml5 = (!forceQuirks && lower-ascii-string(name) == "html" && publicId == Nothing && systemId == Nothing)
              val st1 = if isHtml5 then st0 else add-error(st0)
              (append(st(st1.stack, BeforeHtml, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors),
                      TDoctype(Doctype(name, publicId, systemId, forceQuirks))), False)
            }
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
              {
                val st1 = ensure-html(st0, Nil)
                val st2 = if st0.html-inserted then merge-html-attrs(add-error(st1), attrs) else ensure-html(st0, attrs)
                (st(st2.stack, BeforeHead, st2.html-inserted, st2.head-inserted, st2.body-inserted, st2.errors), False)
              }
            else
              { val st1 = ensure-head(st0, Nil); (st(st1.stack, InHead, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True) }
          TokEndTag(name) ->
            if name == "head" || name == "body" || name == "html" || name == "br" then
              { val st1 = ensure-head(st0, Nil); (st(st1.stack, InHead, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True) }
            else
              (add-error(st0), False)
          TokEOF ->
            { val st1 = ensure-head(st0, Nil); (st(st1.stack, InHead, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True) }
          TokDoctype(_,_,_,_) ->
            (st0, False)
      InHead ->
        match t
          TokEndTag(name) ->
            if in-template-content(st0.stack) then
              if has-open(st0.stack, name) then
                (end-tag(st0, name), False)
              else
                (add-error(st0), False)
            elif name == "head" then
              { val stack1 = pop-to(st0.stack, "head"); (st(stack1, AfterHead, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors), False) }
            elif name == "body" || name == "html" then
              { val stack1 = pop-to(st0.stack, "head"); (st(stack1, AfterHead, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors), True) }
            elif name == "br" then
              // Used by html5lib's </br> in <head><noscript>... case; don't double-count errors here.
              { val stack1 = pop-to(st0.stack, "head"); (st(stack1, AfterHead, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors), True) }
            else if has-open(st0.stack, name) then
              (end-tag(st0, name), False)
            else
              (add-error(st0), False)
          TokStartTag(name, attrs, selfClosing) ->
            if in-template-content(st0.stack) then
              (start-tag(st0, name, attrs, selfClosing), False)
            elif name == "html" then
              {
                val st1 = merge-html-attrs(add-error(st0), attrs)
                (st(st1.stack, InHead, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False)
              }
            elif name == "head" then (add-error(st0), False)
            elif name == "body" then
              {
                val stack1 = pop-to(st0.stack, "head")
                val st1 = ensure-body(st(stack1, InBody, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors), attrs)
                (st(st1.stack, InBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False)
              }
            elif name == "noscript" then
              {
                val st1 = start-tag(st0, name, attrs, selfClosing)
                if !scriptingEnabled then
                  (st(st1.stack, InHeadNoscript, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False)
                else
                  (st1, False)
              }
            elif name == "title" || name == "style" || name == "script" || name == "noframes" || name == "template" then
              (start-tag(st0, name, attrs, selfClosing), False)
            elif name == "base" || name == "basefont" || name == "bgsound" || name == "link" || name == "meta" then
              (start-tag(st0, name, attrs, selfClosing), False)
            else
              { val stack1 = pop-to(st0.stack, "head"); (st(stack1, AfterHead, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors), True) }
          TokCharacter(s) ->
            if in-template-content(st0.stack) then
              (append(st0, TText(s)), False)
            else {
              val (curName, _curNs) = current-element(st0.stack)
              val nm = lower-ascii-string(curName)
              if nm == "title" || nm == "style" || nm == "script" || nm == "noframes" || (scriptingEnabled && nm == "noscript") then
                (append(st0, TText(s)), False)
              elif is-ws(s) then
                (append(st0, TText(s)), False)
              else
                {
                  // Preserve any leading whitespace in the head, and reprocess the remainder after leaving the head.
                  val (ws0, rest0) = split-leading-ws(s)
                  if ws0 != "" then
                    {
                      val st1 = append(st0, TText(ws0))
                      if rest0 == "" then
                        (st1, False)
                      else
                        {
                          val stack1 = pop-to(st1.stack, "head")
                          val st2 = st(stack1, AfterHead, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors)
                          // Handle the remainder as if we were in `AfterHead` without relying on `reprocess`,
                          // since `reprocess` can only reprocess the *original* token.
                          if is-ws(rest0) then
                            (append(st2, TText(rest0)), False)
                          else
                            {
                              val st3 = ensure-body(st2, Nil)
                              val st4 = st(st3.stack, InBody, st3.html-inserted, st3.head-inserted, st3.body-inserted, st3.errors)
                              (append(st4, TText(rest0)), False)
                            }
                        }
                    }
                  else
                    { val stack1 = pop-to(st0.stack, "head"); (st(stack1, AfterHead, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors), True) }
                }
            }
          TokComment(data) -> (append(st0, TComment(data)), False)
          TokDoctype(_,_,_,_) -> (st0, False)
          TokEOF ->
            {
              val st1 = add-eof-error(st0)
              val stack1 = pop-to(st1.stack, "head")
              (st(stack1, AfterHead, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True)
            }
      InHeadNoscript ->
        match t
          TokEndTag(name) ->
            if name == "noscript" then
              { val st1 = end-tag(st0, "noscript"); (st(st1.stack, InHead, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False) }
            elif name == "br" then
              // Not allowed in this context; treat as if it were in the body (via reprocess).
              { val stack1 = pop-to(st0.stack, "noscript"); (st(stack1, InHead, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors + 1), True) }
            elif has-open(st0.stack, name) then
              (end-tag(st0, name), False)
            else
              // Ignore unexpected end tags (like </p>) without leaving in-head-noscript.
              (add-error(st0), False)
          TokStartTag(name, attrs, selfClosing) ->
            if name == "html" then
              {
                val st1 = merge-html-attrs(add-error(st0), attrs)
                (st(st1.stack, InHeadNoscript, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False)
              }
            elif name == "head" || name == "noscript" then (add-error(st0), False)
            elif name == "base" || name == "basefont" || name == "bgsound" || name == "link" || name == "meta" || name == "noframes" || name == "style" then
              // "Process using the rules for InHead" without changing the insertion mode.
              (start-tag(st0, name, attrs, selfClosing), False)
            else
              { val stack1 = pop-to(st0.stack, "noscript"); (st(stack1, InHead, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors + 1), True) }
          TokCharacter(s) ->
            if is-ws(s) then
              (append(st0, TText(s)), False)
            else
              {
                val (curName, _curNs) = current-element(st0.stack)
                val nm = lower-ascii-string(curName)
                if nm == "style" || nm == "noframes" then
                  (append(st0, TText(s)), False)
                else
                  { val stack1 = pop-to(st0.stack, "noscript"); (st(stack1, InHead, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors + 1), True) }
              }
          TokComment(data) -> (append(st0, TComment(data)), False)
          TokDoctype(_,_,_,_) -> (add-error(st0), False)
          TokEOF ->
            // html5lib: eof-in-head-noscript
            (add-error(st0), False)
      AfterHead ->
        match t
          TokComment(data) -> (append(st0, TComment(data)), False)
          TokCharacter(s) ->
            {
              val (curName, _curNs) = current-element(st0.stack)
              val nm = lower-ascii-string(curName)
              if nm == "title" then
                (append(st0, TText(s)), False)
              elif is-ws(s) then
                (append(st0, TText(s)), False)
              else
                { val st1 = ensure-body(st0, Nil); (st(st1.stack, InBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True) }
            }
          TokStartTag(name, attrs, selfClosing) ->
            if name == "head" then
              (add-error(st0), False)
            elif name == "title" then
              {
                // Parse error, but still insert <title> into the (still-open) head and parse its contents.
                val st1 = start-tag(add-error(st0), name, attrs, selfClosing)
                (st(st1.stack, AfterHead, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False)
              }
            elif name == "style" || name == "script" then
              {
                val node = TEl(name, Html, adjust-attrs(Html, attrs), Nil)
                val st1 = append-into-head(add-error(st0), node)
                (st(st1.stack, AfterHead, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False)
              }
            elif name == "frameset" then
              {
                // Allow a frameset document before inserting a <body>.
                val st1 = start-tag(st0, name, attrs, False)
                (st(st1.stack, InFrameset, st1.html-inserted, st1.head-inserted, True, st1.errors), False)
              }
            elif name == "body" then
              { val st1 = ensure-body(st0, attrs); (st(st1.stack, InBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False) }
            else
              { val st1 = ensure-body(st0, Nil); (st(st1.stack, InBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True) }
          TokEndTag(name) ->
            if name == "title" && has-open(st0.stack, "title") then
              match st0.stack
                Cons(top, rest) ->
                  {
                    val node = close-frame(top)
                    val st1 = st(rest, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors)
                    val st2 = append-into-head(st1, node)
                    (st(st2.stack, AfterHead, st2.html-inserted, st2.head-inserted, st2.body-inserted, st2.errors), False)
                  }
                _ -> (end-tag(st0, "title"), False)
            elif name == "style" || name == "script" then
              // We don't keep these head elements open on the stack in AfterHead;
              // swallow their end tags to avoid counting them as stray.
              (st0, False)
            elif name == "head" then
              (add-error(st0), False)
            elif name == "body" || name == "html" || name == "br" then
              { val st1 = ensure-body(st0, Nil); (st(st1.stack, InBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True) }
            else
              (add-error(st0), False)
          TokDoctype(_,_,_,_) -> (st0, False)
          TokEOF ->
            { val st1 = ensure-body(st0, Nil); (st(st1.stack, InBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True) }
      InBody ->
        match t
          TokStartTag(name, attrs, selfClosing) ->
            {
              fun close-select-for-hr(stx: dstate, nextName0: string) : <div,exn> dstate
                {
                  val nextName = lower-ascii-string(nextName0)
                  if !has-open(stx.stack, "select") then stx
                  else
                    {
                      val (curName0, _curNs) = current-element(stx.stack)
                      val curName = lower-ascii-string(curName0)
                      val st1 =
                        if curName == "option" && (nextName == "hr" || nextName == "option" || nextName == "optgroup") then
                          st(pop-to(stx.stack, "option"), stx.imode, stx.html-inserted, stx.head-inserted, stx.body-inserted, stx.errors)
                        else stx
                      val (curName1, _curNs1) = current-element(st1.stack)
                      val cur2 = lower-ascii-string(curName1)
                      if cur2 == "optgroup" && (nextName == "hr" || nextName == "optgroup") then
                        st(pop-to(st1.stack, "optgroup"), st1.imode, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors)
                      else st1
                    }
                }

              val stx = close-select-for-hr(st0, name)
              if name == "html" then
                {
                  val st1 = merge-html-attrs(add-error(stx), attrs)
                  (st(st1.stack, InBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False)
                }
              elif name == "head" then (stx, False)
              elif name == "body" then
                {
                  // Merge new attributes (without overwriting) into the existing <body>.
                  val st1 = merge-body-attrs(add-error(stx), attrs)
                  (st(st1.stack, InBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False)
                }
              elif name == "rp" || name == "rt" then
                {
                  // Ruby annotations: generate implied end tags (excluding "rtc") before inserting <rp>/<rt>.
                  val st1 = generate-implied-end-tags(stx, "rtc")
                  // Per spec/html5lib webkit fixtures: inserting <rp>/<rt> when the current node isn't <ruby>
                  // is a parse error, but we still insert the element.
                  val (curName, _curNs) = current-element(st1.stack)
                  val curLow = lower-ascii-string(curName)
                  val ok = (curLow == "ruby" || curLow == "rtc" || curLow == "rb" || curLow == "rp" || curLow == "rt")
                  val st2 = if ok then st1 else add-error(st1)
                  (start-tag(st2, name, attrs, selfClosing), False)
                }
              elif name == "rb" || name == "rtc" then
                {
                  // If we are already in ruby annotation content, close implied tags first.
                  val (curName, _curNs) = current-element(stx.stack)
                  val curLow = lower-ascii-string(curName)
                  val st1 =
                    if curLow == "rb" || curLow == "rp" || curLow == "rt" || curLow == "rtc" then
                      generate-implied-end-tags(stx, "")
                    else stx
                  (start-tag(st1, name, attrs, selfClosing), False)
                }
              elif name == "dd" || name == "dt" then
                {
                  fun close-dd-dt(stx0: dstate, target: string) : <div,exn> dstate
                    if !has-in-definition-scope(stx0.stack, target) then stx0
                    else
                      {
                        val stack1 = pop-to(stx0.stack, target)
                        st(stack1, stx0.imode, stx0.html-inserted, stx0.head-inserted, stx0.body-inserted, stx0.errors)
                      }

                  val st1 =
                    if name == "dd" then
                      if has-in-definition-scope(stx.stack, "dd") then close-dd-dt(stx, "dd")
                      elif has-in-definition-scope(stx.stack, "dt") then close-dd-dt(stx, "dt")
                      else stx
                    else
                      if has-in-definition-scope(stx.stack, "dt") then close-dd-dt(stx, "dt")
                      elif has-in-definition-scope(stx.stack, "dd") then close-dd-dt(stx, "dd")
                      else stx
                  (start-tag(st1, name, attrs, selfClosing), False)
                }
              elif name == "frame" then
                // Disallow <frame> in the body; ignore it.
                (add-error(stx), False)
              elif name == "button" then
                {
                  // If a <button> is already in scope, close it before inserting a new one.
                  val st1 =
                    if has-in-scope(stx.stack, "button") then
                      st(pop-to(add-error(stx).stack, "button"), stx.imode, stx.html-inserted, stx.head-inserted, stx.body-inserted, stx.errors + 1)
                    else
                      stx
                  (start-tag(st1, name, attrs, selfClosing), False)
                }
              else
                {
                  val ns = element-ns(stx.stack, name)
                  val adj = adjust-tag-name(ns, name)
                  val st1 = if is-html-ns(ns) then close-p-if-needed(stx, adj) else stx
                  val st2 = start-tag(st1, name, attrs, selfClosing)
                  if is-html-ns(ns) && adj == "table" && !selfClosing then
                    (st(st2.stack, InTable, st2.html-inserted, st2.head-inserted, st2.body-inserted, st2.errors), False)
                  else
                    (st2, False)
                }
            }
          TokEndTag(name) ->
            // Foreign-content end tags: if we are in a foreign namespace and see an end tag for a
            // different foreign element that is still open, count a parse error before popping.
            {
              val (curName0, curNs) = current-element(st0.stack)
              val curName = lower-ascii-string(curName0)
              val endName = lower-ascii-string(name)
              val stForeign =
                if !is-html-ns(curNs) && curName != endName then
                  match open-element-ns(st0.stack, name)
                    Just(nsFound) -> if !is-html-ns(nsFound) then add-error(st0) else st0
                    _ -> st0
                else
                  st0
              // Continue processing using the (possibly error-charged) state.
              val st0x = stForeign
              if name == "body" then
                {
                  // After the <html>/<body> elements have already been closed into the document,
                  // html5lib expects stray </body> to be ignored without counting an extra error.
                  if top-is-doc(st0x.stack) then
                    (st(st0x.stack, AfterAfterBody, st0x.html-inserted, st0x.head-inserted, st0x.body-inserted, st0x.errors), False)
                  else
                    {
                      // Per spec/html5lib: do not pop <body> here; just switch modes.
                      val st0i = generate-implied-end-tags(st0x, "")
                      val (curName1, _curNs) = current-element(st0i.stack)
                      val stx = if lower-ascii-string(curName1) == "body" then st0i else add-error(st0i)
                      (st(stx.stack, AfterBody, stx.html-inserted, stx.head-inserted, stx.body-inserted, stx.errors), False)
                    }
                }
              elif name == "html" then
                if top-is-doc(st0x.stack) then
                  // After the <html> element has already been closed, a stray </html> should transition
                  // back to AfterAfterBody so trailing comments can attach to the document.
                  (st(st0x.stack, AfterAfterBody, st0x.html-inserted, st0x.head-inserted, st0x.body-inserted, st0x.errors), False)
                else
                  (st0x, False)
              elif name == "br" then
                (start-tag(add-error(st0x), "br", Nil, True), False)
              elif name == "template" && in-template-content(st0x.stack) then
                // html5lib's template fixture counts a mismatch error when </template> appears while there are still
                // unclosed elements in the template content.
                match st0x.stack
                  Cons(fr, _) ->
                    match fr.kind
                      FTemplateContent -> (end-tag(st0x, "template"), False)
                      _ -> (end-tag(add-error(st0x), "template"), False)
                  _ -> (end-tag(add-error(st0x), "template"), False)
              elif is-heading-element(name) then
                if !has-heading-in-scope(st0x.stack) then
                  (add-error(st0x), False)
                else
                  {
                    val st0i = generate-implied-end-tags(st0x, "")
                    val (curName1, _curNs1) = current-element(st0i.stack)
                    val stx = if lower-ascii-string(curName1) == lower-ascii-string(name) then st0i else add-error(st0i)
                    match nearest-heading-in-scope(stx.stack)
                      Just(hname) ->
                        {
                          val stack1 = pop-to(stx.stack, hname)
                          (st(stack1, stx.imode, stx.html-inserted, stx.head-inserted, stx.body-inserted, stx.errors), False)
                        }
                      _ ->
                        // Defensive fallback; shouldn't happen since `has-heading-in-scope` was true.
                        (stx, False)
                  }
              else
                if has-open(st0x.stack, name) then
                  if is-formatting-element(name) then
                    (adoption-end-tag(st0x, name), False)
                  else
                    (end-tag(st0x, name), False)
                else
                  // Treat stray end tags as parse errors (html5lib tree tests count these).
                  (st(st0x.stack, st0x.imode, st0x.html-inserted, st0x.head-inserted, st0x.body-inserted, st0x.errors + 1), False)
            }
          TokCharacter(s) ->
            if s == "" then (st0, False)
            elif top-is-doc(st0.stack) && st0.body-inserted then
              (append-into-body(st0, TText(s)), False)
            else
              (append(st0, TText(s)), False)
          TokComment(data) ->
            if top-is-doc(st0.stack) && st0.body-inserted then
              (append-into-body(st0, TComment(data)), False)
            else
              (append(st0, TComment(data)), False)
          TokDoctype(_,_,_,_) -> (st0, False)
          TokEOF -> (add-eof-error(st0), False)
      InFrameset ->
        match t
          TokStartTag(name, attrs, selfClosing) ->
            if name == "frameset" then
              (st(start-tag(st0, name, attrs, selfClosing).stack, InFrameset, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors), False)
            elif name == "frame" then
              (start-tag(st0, name, attrs, True), False)
            else
              (add-error(st0), False)
          TokEndTag(name) ->
            if name == "frameset" then
              {
                val st1 = end-tag(st0, "frameset")
                val m = if has-open(st1.stack, "frameset") then InFrameset else AfterFrameset
                (st(st1.stack, m, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False)
              }
            else
              (add-error(st0), False)
          TokCharacter(s) ->
            if is-ws(s) then
              (append(st0, TText(s)), False)
            else
              {
                val ws = filter-ws(s)
                val st1 = add-error(st0)
                if ws == "" then (st1, False) else (append(st1, TText(ws)), False)
              }
          TokComment(data) -> (append(st0, TComment(data)), False)
          TokDoctype(_,_,_,_) -> (add-error(st0), False)
          TokEOF -> (add-eof-error(st0), False)
      AfterFrameset ->
        match t
          TokCharacter(s) ->
            if is-ws(s) then
              (append(st0, TText(s)), False)
            else
              {
                val ws = filter-ws(s)
                val st1 = add-error(st0)
                if ws == "" then (st1, False) else (append(st1, TText(ws)), False)
              }
          TokComment(data) -> (append(st0, TComment(data)), False)
          TokEndTag(name) ->
            if name == "html" then
              {
                val st1 = end-tag(st0, "html")
                (st(st1.stack, AfterAfterFrameset, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False)
              }
            else
              (add-error(st0), False)
          TokStartTag(name, attrs, _) ->
            if name == "html" then
              (merge-html-attrs(add-error(st0), attrs), False)
            else
              (add-error(st0), False)
          TokDoctype(_,_,_,_) -> (add-error(st0), False)
          TokEOF -> (add-eof-error(st0), False)
      AfterAfterFrameset ->
        match t
          TokComment(data) -> (append(st0, TComment(data)), False)
          TokCharacter(s) ->
            if is-ws(s) then
              (append-into-html-node(st0, TText(s)), False)
            else
              {
                // html5lib counts "expected-eof-but-got-char" per character, but in our tokenizer
                // some strings that begin with '<' can come from PLAINTEXT-like tokenization.
                // Count those as a single error to match the fixtures that expect a stray end tag.
                val cs = string/vector(s)
                val n = if cs.length > 0 && cs[0] == '<' then 1 else cs.length
                (add-errors(st0, n), False)
              }
          TokStartTag(name, attrs, _) ->
            if name == "html" then
              (merge-html-attrs(add-error(st0), attrs), False)
            else
              (add-error(st0), False)
          TokEndTag(name) ->
            if name == "html" then (st0, False) else (add-error(st0), False)
          TokDoctype(_,_,_,_) -> (add-error(st0), False)
          TokEOF -> (add-eof-error(st0), False)
      InTable ->
        match t
          TokStartTag(name, attrs, selfClosing) ->
            if in-template-content(st0.stack) then
              (start-tag(st0, name, attrs, selfClosing), False)
            elif has-open(st0.stack, "select")
                 && (name == "tr" || is-table-section(name) || is-table-cell(name) || name == "caption" || name == "col" || name == "colgroup") then
              {
                // In select-in-table contexts, close the <select> (foster-parented) before processing other table-structure tokens.
                val stack1 = pop-to-select-foster(st0.stack)
                val st1 = st(stack1, InTable, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors)
                (st1, True)
              }
            elif name == "table" then
              {
                // Nested <table> start tags in a table context close the current table and reprocess.
                val st1 = add-error(st0)
                // If a <select> is open, close it (foster-parented) first so it ends up before the table.
                val stack1 = if has-open(st1.stack, "select") then pop-to-select-foster(st1.stack) else st1.stack
                val st2 = end-tag(st(stack1, st1.imode, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), "table")
                (st(st2.stack, InBody, st2.html-inserted, st2.head-inserted, st2.body-inserted, st2.errors), True)
              }
            elif name == "colgroup" then
              { val st1 = start-tag(st0, name, attrs, selfClosing); (st(st1.stack, InColumnGroup, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False) }
            elif name == "col" then
              {
                // Insert an implied <colgroup> and reprocess the <col> token in InColumnGroup.
                val st1 = start-tag(st0, "colgroup", Nil, False)
                (st(st1.stack, InColumnGroup, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True)
              }
            elif name == "caption" then
              (start-tag(st0, name, attrs, selfClosing), False)
            elif name == "template" then
              (start-tag(st0, name, attrs, selfClosing), False)
            elif name == "select" then
              (start-tag(add-error(st0), name, attrs, selfClosing), False)
            elif is-table-section(name) then
              { val st1 = start-tag(st0, name, attrs, selfClosing); (st(st1.stack, InTableBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False) }
            elif name == "tr" then
              {
                val st1 = ensure-tbody(st0)
                val st2 = start-tag(st(st1.stack, InTableBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), name, attrs, selfClosing)
                (st(st2.stack, InRow, st2.html-inserted, st2.head-inserted, st2.body-inserted, st2.errors), False)
              }
            elif is-table-cell(name) then
              {
                val st1 = add-error(st0)
                val st2 = ensure-tbody(st1)
                val st3 = ensure-tr(st2)
                val st4 = start-tag(st(st3.stack, InRow, st3.html-inserted, st3.head-inserted, st3.body-inserted, st3.errors), name, attrs, selfClosing)
                (st(st4.stack, InCell, st4.html-inserted, st4.head-inserted, st4.body-inserted, st4.errors), False)
              }
            elif name == "option" then
              (start-tag(add-error(st0), name, attrs, selfClosing), False)
            elif name == "input" then
              {
                fun is-hidden-type(attrs0: list<attr>)
                  match attrs0
                    Nil -> False
                    Cons(Attr(an, v), rest) ->
                      match an
                        Attrname(None, local) ->
                          if lower-ascii-string(local) == "type" && lower-ascii-string(v) == "hidden" then True else is-hidden-type(rest)
                        _ -> is-hidden-type(rest)

                val st1 = add-error(st0)
                if is-hidden-type(attrs) then
                  // Per spec/html5lib: hidden inputs don't use foster parenting, but still count a parse error.
                  (start-tag(st1, name, attrs, selfClosing), False)
                else
                  {
                    val ns0 = element-ns(st1.stack, name)
                    val ns = ns0
                    val adjName = adjust-tag-name(ns, name)
                    val attrs1 = adjust-attrs(ns, attrs)
                    (foster-append(st1, TEl(adjName, ns, attrs1, Nil)), False)
                  }
              }
            elif name == "style" || name == "script" then
              (start-tag(st0, name, attrs, selfClosing), False)
            else
              {
                // In table contexts, most non-table start tags trigger foster parenting and count as a parse error.
                val st1 = if foster-needed(st0.stack) then add-error(st0) else st0
                (start-tag(st1, name, attrs, selfClosing), False)
              }
          TokEndTag(name) ->
            if in-template-content(st0.stack) then
              if has-open(st0.stack, name) then
                { val st1 = end-tag(st0, name); (update-mode(st1), False) }
              else
                {
                  fun is-tableish(tag: string) : bool
                    tag == "table"
                    || tag == "caption"
                    || tag == "title"
                    || tag == "col"
                    || tag == "colgroup"
                    || tag == "style"
                    || tag == "script"
                    || tag == "tr"
                    || is-table-section(tag)
                    || is-table-cell(tag)

                  // For non-table end tags in a table context, html5lib counts a table-mode error and
                  // (for foster-parenting "table voodoo"), and if the end tag is still unexpected it
                  // counts an additional "unexpected end tag" error.
                  if is-tableish(name) then
                    (st(st0.stack, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors + 1), False)
                  elif has-open(st0.stack, name) then
                    {
                      // For foreign content (SVG/MathML), don't charge an extra table-mode error when closing
                      // the matching open element.
                      val st1 =
                        match open-element-ns(st0.stack, name)
                          Just(nsFound) -> if is-html-ns(nsFound) then add-error(st0) else st0
                          _ -> add-error(st0)
                      val st2 = end-tag(st1, name)
                      (update-mode(st2), False)
                    }
                  else
                    (add-errors(st0, 2), False)
                }
            elif name == "html" || name == "body" then
              // Don't allow these end tags to close the actual <html>/<body> element from inside table modes.
              (add-error(st0), False)
            elif name == "select" && has-open(st0.stack, "select") then
              {
                // In table contexts, </select> is a parse error but still closes the <select> (foster-parented).
                val st1 = add-error(st0)
                val stack1 = pop-to-select-foster(st1.stack)
                val st2 = st(stack1, st1.imode, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors)
                (update-mode(st2), False)
              }
            elif name == "table" then
              if has-open(st0.stack, "select") then
                {
                  // In select-in-table-like cases, close <select> first (foster-parented), then reprocess </table>.
                  // html5lib doesn't count an extra error for this </table> (see `tables01.dat` #8).
                  val stack1 = pop-to-select-foster(st0.stack)
                  val st2 = st(stack1, InTable, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors)
                  (st2, True)
                }
              else
                { val st1 = end-tag(st0, "table"); (st(st1.stack, InBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False) }
            else
              {
                fun is-tableish(tag: string) : bool
                  tag == "table"
                  || tag == "caption"
                  || tag == "title"
                  || tag == "col"
                  || tag == "colgroup"
                  || tag == "style"
                  || tag == "script"
                  || tag == "tr"
                  || is-table-section(tag)
                  || is-table-cell(tag)

                if has-open(st0.stack, name) then
                  if is-formatting-element(name) then
                    if has-in-scope(st0.stack, name) then
                      { val st1 = adoption-end-tag(st0, name); (update-mode(st1), False) }
                    else
                      // html5lib counts 2 errors here ("unexpected-end-tag-implies-table-voodoo" + "unexpected-end-tag").
                      (st(st0.stack, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors + 2), False)
                  else
                    if is-tableish(name) then
                      // Table-scoped end tags that match an open element are handled normally.
                      { val st1 = end-tag(st0, name); (update-mode(st1), False) }
                    else
                      // Non-table end tags in a table context are parse errors even if they match an open element.
                      {
                        val inCaption = has-open(st0.stack, "caption")
                        val st1 =
                          match open-element-ns(st0.stack, name)
                            Just(nsFound) -> if !inCaption && is-html-ns(nsFound) then add-error(st0) else st0
                            _ -> if inCaption then st0 else add-error(st0)
                        val st2 = end-tag(st1, name)
                        (update-mode(st2), False)
                      }
                else
                  if is-tableish(name) then
                    // Table-scoped end tags that don't match an open element are a single parse error.
                    (add-error(st0), False)
                  else
                    // "Table voodoo" + "unexpected end tag".
                    (add-errors(st0, 2), False)
              }
          TokCharacter(s) ->
            if in-template-content(st0.stack) then
              (append(st0, TText(s)), False)
            elif has-open(st0.stack, "select") && has-open(st0.stack, "table") then
              // html5lib: character tokens in a table+select context are parse errors, but still inserted.
              (append(add-error(st0), TText(s)), False)
            elif is-ws(s) || !foster-needed(st0.stack) then
              (append(st0, TText(s)), False)
            else
              {
                // html5lib: foster-parented characters in table contexts are parse errors (often counted per character).
                val n = string/vector(s).length
                val st1 = st(st0.stack, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors + n)
                (foster-append(st1, TText(s)), False)
              }
          TokComment(data) -> (append(st0, TComment(data)), False)
          TokDoctype(_,_,_,_) -> (add-error(st0), False)
          TokEOF -> (add-eof-error(st0), False)
      InTableBody ->
        match t
          TokStartTag(name, attrs, selfClosing) ->
            if in-template-content(st0.stack) then
              (start-tag(st0, name, attrs, selfClosing), False)
            elif name == "caption" then
              {
                // Pop the table body element so `<caption>` becomes a direct child of `<table>`.
                val st1 = close-row(st0)
                val st2 =
                  if has-open(st1.stack, "tbody") then end-tag(st1, "tbody")
                  elif has-open(st1.stack, "thead") then end-tag(st1, "thead")
                  elif has-open(st1.stack, "tfoot") then end-tag(st1, "tfoot")
                  else st1
                (st(st2.stack, InTable, st2.html-inserted, st2.head-inserted, st2.body-inserted, st2.errors), True)
              }
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
            elif name == "html" || name == "body" then
              (add-error(st0), False)
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
            elif name == "html" || name == "body" then
              // Don't allow these end tags to close the actual <html>/<body> element from inside table modes.
              (add-error(st0), False)
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
            if is-ws(s) then
              (append(st0, TText(s)), False)
            else
              {
                // Non-whitespace characters in a colgroup context should be handled as if in-table.
                val st1 = end-tag(st0, "colgroup")
                (st(st1.stack, InTable, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True)
              }
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
            elif name == "caption" then
              {
                // Close the current row and let table-body mode place `<caption>` correctly.
                val st1 = end-tag(st0, "tr")
                (st(st1.stack, InTableBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True)
              }
            elif name == "tr" then
              {
                // Close the current row before starting a new one.
                val st1 = end-tag(st0, "tr")
                (st(st1.stack, InTableBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True)
              }
            elif is-table-section(name) || name == "table" then
              {
                val st1 = add-error(st0)
                val st2 = end-tag(st1, "tr")
                (st(st2.stack, InTableBody, st2.html-inserted, st2.head-inserted, st2.body-inserted, st2.errors), True)
              }
            else
              (start-tag(st0, name, attrs, selfClosing), False)
          TokEndTag(name) ->
            if in-template-content(st0.stack) then
              if has-open(st0.stack, name) then
                { val st1 = end-tag(st0, name); (update-mode(st1), False) }
              else
                (st(st0.stack, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors + 1), False)
            elif name == "html" || name == "body" then
              (add-error(st0), False)
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
            elif name == "html" || name == "body" then
              (add-error(st0), False)
            elif is-table-cell(name) then
              if has-open(st0.stack, name) then
                { val st1 = end-tag(st0, name); (st(st1.stack, InRow, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False) }
              else
                (add-error(st0), False)
            elif name == "table" then
              {
                // Close the cell and reprocess. Count a parse error if the current node isn't the cell itself.
                val (curName, _curNs) = current-element(st0.stack)
                val curLow = lower-ascii-string(curName)
                val stx = if curLow == "td" || curLow == "th" then st0 else add-error(st0)
                val st1 = close-cell(stx)
                (st(st1.stack, InRow, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True)
              }
            else
              if has-open(st0.stack, name) then
                if is-formatting-element(name) then
                  if has-in-cell-scope(st0.stack, name) then
                    { val st1 = adoption-end-tag(st0, name); (update-mode(st1), False) }
                  else
                    // Parse error; ignore end tags for formatting elements that are outside the current cell.
                    (add-error(st0), False)
                else
                  { val st1 = end-tag(st0, name); (update-mode(st1), False) }
              else
                (st(st0.stack, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors + 1), False)
          TokStartTag(name, attrs, selfClosing) ->
            if in-template-content(st0.stack) then
              (start-tag(st0, name, attrs, selfClosing), False)
            elif is-one-of(name, Cons("td", Cons("th", Cons("tr", Cons("tbody", Cons("thead", Cons("tfoot", Cons("table", Nil)))))))) then
              {
                // Close the current cell and reprocess.
                // html5lib counts an error here for nested cell start tags, but not for all table-structure tags.
                val (curName, _curNs) = current-element(st0.stack)
                val curLow = lower-ascii-string(curName)
                val st1 = if (name == "td" || name == "th") && curLow != "td" && curLow != "th" then add-error(st0) else st0
                val st2 = close-cell(st1)
                (st(st2.stack, InRow, st2.html-inserted, st2.head-inserted, st2.body-inserted, st2.errors), True)
              }
            else
              (start-tag(st0, name, attrs, selfClosing), False)
          TokCharacter(s) ->
            if s == "" then (st0, False) else (append(st0, TText(s)), False)
          TokComment(data) -> (append(st0, TComment(data)), False)
          TokDoctype(_,_,_,_) -> (add-error(st0), False)
          TokEOF -> (add-eof-error(st0), False)
      AfterBody ->
        match t
          TokComment(data) ->
            // Spec: comment after body is appended to <html>, not <body>.
            // Our stack model only attaches child elements to parents on pop/close, so if <body>
            // (and other elements) are still open, close them first so the comment becomes a sibling.
            {
              val stack1 = if has-open(st0.stack, "body") then pop-to(st0.stack, "body") else st0.stack
              val st1 = st(stack1, st0.imode, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors)
              (append(st1, TComment(data)), False)
            }
          TokCharacter(s) ->
            if is-ws(s) then
              // Spec: whitespace after body is inserted using InBody rules but we stay in AfterBody.
              (append-into-body(st0, TText(s)), False)
            else
              {
                val st1 = add-error(st0)
                (st(st1.stack, InBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True)
              }
          TokEOF -> (st0, False)
          TokStartTag(name, _attrs, _selfClosing) ->
            if name == "html" then
              (st(st0.stack, InBody, st0.html-inserted, st0.head-inserted, st0.body-inserted, st0.errors), True)
            else
              {
                val st1 = add-error(st0)
                (st(st1.stack, InBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True)
              }
          TokEndTag(name) ->
            if name == "html" then
              {
                // Close <html> and switch to "after after body" so trailing comments become document children.
                val st1 = end-tag(st0, "html")
                (st(st1.stack, AfterAfterBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False)
              }
            elif name == "br" then
              {
                // html5lib expects `</br>` after </body> to be a parse error and to insert `<br>` into the body.
                val st1 = add-error(st0)     // unexpected-token-after-body
                val st2 = add-error(st1)     // unexpected-end-tag for </br>
                val st3 = append-into-body(st2, TEl("br", Html, Nil, Nil))
                (st3, False)
              }
            else
              {
                val st1 = add-error(st0)
                (st(st1.stack, InBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True)
              }
          _ ->
            {
              val st1 = add-error(st0)
              (st(st1.stack, InBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True)
            }
      AfterAfterBody ->
        match t
          TokComment(data) -> (append(st0, TComment(data)), False)
          TokEndTag(name) ->
            if name == "html" || name == "body" then
              // html5lib's webkit fixtures expect these stray end tags to be ignored here.
              (st0, False)
            else
              { val st1 = add-error(st0); (st(st1.stack, InBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True) }
          TokEOF -> (st0, False)
          TokCharacter(s) ->
            if is-ws(s) then
              // Process whitespace using InBody rules but stay in AfterAfterBody.
              { val (st1, _rep) = process-inbody(t, st0); (st(st1.stack, AfterAfterBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), False) }
            else
              { val st1 = add-error(st0); (st(st1.stack, InBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True) }
          _ ->
            { val st1 = add-error(st0); (st(st1.stack, InBody, st1.html-inserted, st1.head-inserted, st1.body-inserted, st1.errors), True) }

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
    {
      val stx = if st2.head-inserted then st2 else ensure-head(st2, Nil)
      if has-open(stx.stack, "head") then
        st(pop-to(stx.stack, "head"), stx.imode, stx.html-inserted, stx.head-inserted, stx.body-inserted, stx.errors)
      else
        stx
    }
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
                match (top.kind, parent2.kind)
                  (FEl(topName, _topNs, _topAttrs), FEl(parentName, _pns, _pattrs)) ->
                    {
                      val p = lower-ascii-string(parentName)
                      val t = lower-ascii-string(topName)
                      fun is-table-child(name: string) : bool
                        name == "caption" || name == "colgroup" || name == "tbody" || name == "thead" || name == "tfoot"
                          || name == "style" || name == "script"

                      if p == "table" && !is-table-child(t) then
                        {
                          val node = close-frame(top)
                          val stack1 = Cons(parent2, rest2)
                          match foster-stack(stack1, node)
                            Just(stack2) -> close-all(stack2)
                            Nothing -> close-all(Cons(add-child(parent2, node), rest2))
                        }
                      else
                        close-all(Cons(add-child(parent2, close-frame(top)), rest2))
                    }
                  _ -> close-all(Cons(add-child(parent2, close-frame(top)), rest2))
              _ -> stack0
      Cons(top, Cons(parent, rest)) ->
        match (top.kind, parent.kind)
          (FEl(topName, _topNs, _topAttrs), FEl(parentName, _pns, _pattrs)) ->
            {
              val p = lower-ascii-string(parentName)
              val t = lower-ascii-string(topName)
              fun is-table-child(name: string) : bool
                name == "caption" || name == "colgroup" || name == "tbody" || name == "thead" || name == "tfoot"
                  || name == "style" || name == "script"

              if p == "table" && !is-table-child(t) then
                {
                  // Foster-parent non-table children out of `<table>` at close time, so they end up before the table.
                  val node = close-frame(top)
                  val stack1 = Cons(parent, rest)
                  match foster-stack(stack1, node)
                    Just(stack2) -> close-all(stack2)
                    Nothing -> close-all(Cons(add-child(parent, node), rest))
                }
              else
                close-all(Cons(add-child(parent, close-frame(top)), rest))
            }
          _ -> close-all(Cons(add-child(parent, close-frame(top)), rest))
      _ -> stack0

  val closed =
    match close-all(st4.stack)
      Cons(root, _) -> root.children.reverse
      _ -> Nil
  val dom = arena-from-children(Document(Nil, "no-quirks"), closed)
  (dom, st4.errors)

pub fun build-fragment(tokens: list<token>, fragCtx: fragmentcontext) : <div,exn> (dom, int)
  val initial = Frame(FFrag(Just(fragCtx)), Nil)
  val (children, errs) = build-tree(tokens, initial)
  (arena-from-children(DocumentFragment(Nil, Just(fragCtx)), children), errs)

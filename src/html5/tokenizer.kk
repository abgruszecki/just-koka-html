module html5/tokenizer

import std/core/string
import html5/dom
import html5/entities
import html5/errors

pub type tokenizer-state {
  Data
  PLAINTEXT
  RCDATA
  RAWTEXT
  ScriptData
  CDATASection
}

pub type token {
  TokDoctype(name: string, publicId: maybe<string>, systemId: maybe<string>, forceQuirks: bool)
  TokStartTag(name: string, attrs: list<attr>, selfClosing: bool)
  TokEndTag(name: string)
  TokComment(data: string)
  TokCharacter(data: string)
  TokEOF
}

pub alias parseerror = errors/parseerror

type st {
  SData
  SRCDATA
  SRAWTEXT
  SScriptData
  SRCDATALessThanSign
  SRCDATAEndTagOpen
  SRCDATAEndTagName
  SRAWTEXTLessThanSign
  SRAWTEXTEndTagOpen
  SRAWTEXTEndTagName
  SScriptDataLessThanSign
  SScriptDataEndTagOpen
  SScriptDataEndTagName
  SScriptDataEscapeStart
  SScriptDataEscapeStartDash
  SScriptDataEscaped
  SScriptDataEscapedDash
  SScriptDataEscapedDashDash
  SScriptDataEscapedLessThanSign
  SScriptDataEscapedEndTagOpen
  SScriptDataEscapedEndTagName
  SScriptDataDoubleEscapeStart
  SScriptDataDoubleEscaped
  SScriptDataDoubleEscapedDash
  SScriptDataDoubleEscapedDashDash
  SScriptDataDoubleEscapedLessThanSign
  SScriptDataDoubleEscapeEnd
  SPlaintext
  SCDataSection
  STagOpen
  SMarkupDeclOpen
  SEndTagOpen
  STagName
  SBeforeAttrName
  SAttrName
  SAfterAttrName
  SBeforeAttrValue
  SAttrValueDQ
  SAttrValueSQ
  SAttrValueUQ
  SAfterAttrValueQ
  SSelfClosingStartTag
  SCommentStart
  SCommentStartDash
  SComment
  SCommentLessThanSign
  SCommentLessThanSignBang
  SCommentLessThanSignBangDash
  SCommentLessThanSignBangDashDash
  SCommentEndDash
  SCommentEnd
  SCommentEndBang
  SBogusComment
  SBeforeDoctypeName
  SDoctypeName
  SAfterDoctypeName
  SAfterDoctypePublicKeyword
  SBeforeDoctypePublicId
  SDoctypePublicIdDQ
  SDoctypePublicIdSQ
  SAfterDoctypePublicId
  SBetweenDoctypePublicAndSystemId
  SAfterDoctypeSystemKeyword
  SBeforeDoctypeSystemId
  SDoctypeSystemIdDQ
  SDoctypeSystemIdSQ
  SAfterDoctypeSystemId
  SBogusDoctype
}

fun is-ascii-alpha(c: char) : bool
  (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')

fun lower-ascii(c: char) : char
  if (c >= 'A' && c <= 'Z') then (c.int + 32).char else c

fun is-ascii-alnum(c: char) : bool
  (c >= '0' && c <= '9') || is-ascii-alpha(c)

fun is-ws(c: char) : bool
  c == ' ' || c == '\n' || c == '\t' || c == '\r' || c == '\u000c'

fun repl-nul(c: char) : char
  if c == '\u0000' then '\uFFFD' else c

fun lower-ascii-string(s: string) : <div,exn> string
  val cs = string/vector(s)
  fun go(i: int, acc: list<char>) : <div,exn> list<char>
    if i >= cs.length then acc.reverse
    else go(i + 1, Cons(lower-ascii(cs[i]), acc))
  string/listchar/string(go(0, Nil))

fun starts-with-ci(cs: vector<char>, start: int, pat: string) : <div,exn> bool
  val ps = string/vector(pat)
  if start + ps.length > cs.length then False else
    {
      var ok := True
      var i := 0
      while(fn(){ ok && i < ps.length }, fn(){
        ok := (lower-ascii(cs[start + i]) == lower-ascii(ps[i]))
        i := i + 1
      })
      ok
    }

fun preprocess(input: string) : <div,exn> vector<char>
  val cs = string/vector(input)
  var out : list<char> := Nil
  var i := 0
  while(fn(){ i < cs.length }, fn(){
    val c0 = cs[i]
    if c0 == '\r' then
      out := Cons('\n', out)
      if (i + 1 < cs.length && cs[i+1] == '\n') then i := i + 2 else i := i + 1
    else
      out := Cons(c0, out)
      i := i + 1
  })
  vector/list/vector(out.reverse)

fun slice-string(cs: vector<char>, start: int, end: int) : <div,exn> string
  // end is exclusive
  var acc : list<char> := Nil
  var i := start
  while(fn(){ i < end && i < cs.length }, fn(){
    acc := Cons(cs[i], acc)
    i := i + 1
  })
  string/listchar/string(acc.reverse)

fun parse-uint(cs: vector<char>, start: int, end: int, base: int) : <div,exn> int
  var n := 0
  var i := start
  while(fn(){ i < end && i < cs.length }, fn(){
    val c = cs[i]
    val d =
      if (c >= '0' && c <= '9') then (c.int - '0'.int)
      elif (base == 16 && c >= 'a' && c <= 'f') then (10 + c.int - 'a'.int)
      elif (base == 16 && c >= 'A' && c <= 'F') then (10 + c.int - 'A'.int)
      else 0
    n := n * base + d
    i := i + 1
  })
  n

fun map-numeric-codepoint(code: int) : int
  // Map Windows-1252 C1 controls as required by the HTML spec.
  match code
    0x80 -> 0x20AC
    0x82 -> 0x201A
    0x83 -> 0x0192
    0x84 -> 0x201E
    0x85 -> 0x2026
    0x86 -> 0x2020
    0x87 -> 0x2021
    0x88 -> 0x02C6
    0x89 -> 0x2030
    0x8A -> 0x0160
    0x8B -> 0x2039
    0x8C -> 0x0152
    0x8E -> 0x017D
    0x91 -> 0x2018
    0x92 -> 0x2019
    0x93 -> 0x201C
    0x94 -> 0x201D
    0x95 -> 0x2022
    0x96 -> 0x2013
    0x97 -> 0x2014
    0x98 -> 0x02DC
    0x99 -> 0x2122
    0x9A -> 0x0161
    0x9B -> 0x203A
    0x9C -> 0x0153
    0x9E -> 0x017E
    0x9F -> 0x0178
    _ -> code

fun sanitize-codepoint(code0: int) : int
  if code0 == 0 then 0xFFFD
  elif code0 > 0x10FFFF then 0xFFFD
  elif (code0 >= 0xD800 && code0 <= 0xDFFF) then 0xFFFD
  else map-numeric-codepoint(code0)

fun find-entity-match(cs: vector<char>, start: int, end: int) : <div,exn> (end: int, value: maybe<string>)
  // Find the longest entity name in cs[start:end] (end is exclusive).
  if end <= start then (end, Nothing) else
    {
      val key = slice-string(cs, start, end)
      match entities/lookup(key)
        Just(v) -> (end, Just(v))
        Nothing -> find-entity-match(cs, start, end - 1)
    }

fun consume-char-ref(cs: vector<char>, pos: int, in-attr: bool)
  : <div,exn> (consumed: int, replacement: maybe<string>, errors: list<string>)
  // `pos` is the index of '&'.
  val len = cs.length
  val next = pos + 1
  if next >= len then (1, Nothing, Nil) else
    val c1 = cs[next]
    if c1 == '#' then
      // Numeric character reference.
      val n2 = next + 1
      if n2 >= len then (1, Nothing, Nil) else
        val c2 = cs[n2]
        val isHex = (c2 == 'x' || c2 == 'X')
        val digitsStart = if isHex then (n2 + 1) else n2
        var j := digitsStart
        while(fn(){
          j < len && (
            (cs[j] >= '0' && cs[j] <= '9') ||
            (isHex && ((cs[j] >= 'a' && cs[j] <= 'f') || (cs[j] >= 'A' && cs[j] <= 'F')))
          )
        }, fn(){ j := j + 1 })
        if j == digitsStart then (1, Nothing, Nil) else
          {
            val hasSemi = (j < len && cs[j] == ';')
            val end = j
            val code = parse-uint(cs, digitsStart, end, if isHex then 16 else 10)
            val safe = sanitize-codepoint(code)
            val s = char/string(safe.char)
            val consumed = (if hasSemi then (j - pos + 1) else (j - pos))
            // html5lib tree-construction fixtures count both legacy + modern numeric-entity errors.
            val isControl = (code < 0x20) || (code >= 0x7F && code <= 0x9F)
            val errs =
              if isControl then
                Cons("illegal-codepoint-for-numeric-entity", Cons("control-character-reference", Nil))
              else
                Nil
            (consumed, Just(s), errs)
          }
    else
      // Named character reference: ASCII alnum only.
      var j := next
      while(fn(){ j < len && is-ascii-alnum(cs[j]) }, fn(){ j := j + 1 })
      if j == next then (1, Nothing, Nil) else
        {
          val hasSemi = (j < len && cs[j] == ';')
          val maxEnd = if hasSemi then (j + 1) else j
          val (k, rep) = find-entity-match(cs, next, maxEnd)
          match rep
            Nothing -> (1, Nothing, Nil)
            Just(v) ->
              {
                val endsSemi = (k > next && k <= len && cs[k - 1] == ';')
                val semErrs =
                  if !endsSemi then
                    Cons("named-entity-without-semicolon", Cons("missing-semicolon-after-character-reference", Nil))
                  else
                    Nil
                if (in-attr && !endsSemi) then
                  {
                    val following = if k < len then cs[k] else '\u0000'
                    if (k < len && (is-ascii-alnum(following) || following == '=')) then
                      (1, Nothing, Nil)
                    else
                      (k - pos, Just(v), semErrs)
                  }
                else
                  (k - pos, Just(v), semErrs)
              }
        }

fun consume-rawtext-endtag(cs: vector<char>, pos: int, lastStartTag: maybe<string>) : <div,exn> (consumed: int, tag: maybe<string>)
  // `pos` is the index of '<' in one of the rawtext-ish states.
  match lastStartTag
    Nothing -> (0, Nothing)
    Just(last0) ->
      {
        val last = lower-ascii-string(last0.trim)
        val len = cs.length
        if pos + 2 >= len then (0, Nothing)
        elif cs[pos] != '<' || cs[pos + 1] != '/' then (0, Nothing)
        else
          {
            val j0 = pos + 2
            if j0 >= len then (0, Nothing)
            else if is-ascii-alpha(cs[j0]) then
              {
                fun scan-name(j: int, acc: list<char>) : <div,exn> (j: int, name: string)
                  if j < len && is-ascii-alnum(cs[j]) then
                    scan-name(j + 1, Cons(lower-ascii(cs[j]), acc))
                  else
                    (j, string/listchar/string(acc.reverse))

                fun scan-ws(j: int) : <div,exn> int
                  if j < len && is-ws(cs[j]) then scan-ws(j + 1) else j

                val (j1, name) = scan-name(j0, Nil)
                val k = scan-ws(j1)
                if k < len && cs[k] == '>' && name != "" && name == last then
                  (k - pos + 1, Just(name))
                else
                  (0, Nothing)
              }
            else
              (0, Nothing)
          }
      }

// M1: a pragmatic subset tokenizer (tokenizer-tests), plus an optional auto-switch mode
// used by tree construction to approximate the spec's treebuilder-driven state changes.
fun tokenize-internal(input: string, initial: tokenizer-state, lastStartTag: maybe<string>, autoSwitch: bool)
  : <div,exn> (tokens: list<token>, errors: list<parseerror>)
  val cs = preprocess(input)
  // Precompute 1-based (line,col) for each codepoint in the preprocessed stream.
  fun positions(cs0: vector<char>) : <div,exn> (vector<int>, vector<int>)
    var ls : list<int> := Nil
    var cs2 : list<int> := Nil
    var line := 1
    var col := 1
    var j := 0
    while(fn(){ j < cs0.length }, fn(){
      ls := Cons(line, ls)
      cs2 := Cons(col, cs2)
      val ch = cs0[j]
      if ch == '\n' then
        { line := line + 1; col := 1 }
      else
        col := col + 1
      j := j + 1
    })
    (vector/list/vector(ls.reverse), vector/list/vector(cs2.reverse))

  val (pos-line, pos-col) = positions(cs)
  var errs : list<parseerror> := Nil
  fun add-err(code: string, at: int)
    val line = if (at >= 0 && at < pos-line.length) then pos-line[at] else 1
    val col = if (at >= 0 && at < pos-col.length) then pos-col[at] else 1
    errs := Cons(errors/Parseerror(code, line, col), errs)
  fun add-ref-errs(at: int, es: list<string>)
    match es
      Nil -> ()
      Cons(code, rest) -> { add-err(code, at); add-ref-errs(at, rest) }
  fun add-eof-in-comment(at: int)
    {
      // html5lib counts both a legacy and a modern error here.
      add-err("eof-in-comment", at)
      add-err("eof-in-comment", at)
    }

  // Token under construction
  var cur-is-end := False
  var cur-name : list<char> := Nil
  var cur-attrs : list<attr> := Nil
  var cur-selfclosing := False
  var cur-attr-name : list<char> := Nil
  var cur-attr-value : list<char> := Nil
  var in-attr := False
  var temp-buffer : list<char> := Nil  // for rawtext/RCDATA/script end tag matching

  // Output
  var out : list<token> := Nil
  var text-acc : list<char> := Nil
  var comment-acc : list<char> := Nil
  var doctype-name : list<char> := Nil
  var doctype-public : maybe<string> := Nothing
  var doctype-system : maybe<string> := Nothing
  var doctype-force := False
  var doctype-id-acc : list<char> := Nil
  var doctype-saw-ws := False
  var last-start := lastStartTag
  var tag-next-state := SData
  var cur-pos := 0
  var pending-endtag-solidus := False
  var endtag-solidus-saw-non-gt := False
  var endtag-attr-error-emitted := False
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
  fun flush-text()
    if text-acc != Nil then
      out := Cons(TokCharacter(string/listchar/string(text-acc.reverse)), out)
      text-acc := Nil

  fun emit-token(t: token)
    flush-text()
    out := Cons(t, out)

  fun finish-attr()
    if in-attr then
      val n = string/listchar/string(cur-attr-name.reverse).trim
      val v = string/listchar/string(cur-attr-value.reverse)
      if n != "" then
        val an = Attrname(None, n)
        if has-attr(an, cur-attrs) then
          add-err("duplicate-attribute", cur-pos)
        else
          cur-attrs := Cons(Attr(an, v), cur-attrs)
      cur-attr-name := Nil
      cur-attr-value := Nil
      in-attr := False

  fun finish-tag()
    finish-attr()
    val name = string/listchar/string(cur-name.reverse).trim
    tag-next-state := SData
    endtag-attr-error-emitted := False
    endtag-solidus-saw-non-gt := False
    if (!cur-is-end && autoSwitch && !cur-selfclosing) then
      match name
        "textarea" -> { last-start := Just(name); tag-next-state := SRCDATA }
        "title" -> { last-start := Just(name); tag-next-state := SRCDATA }
        "style" -> { last-start := Just(name); tag-next-state := SRAWTEXT }
        "xmp" -> { last-start := Just(name); tag-next-state := SRAWTEXT }
        "iframe" -> { last-start := Just(name); tag-next-state := SRAWTEXT }
        "noembed" -> { last-start := Just(name); tag-next-state := SRAWTEXT }
        "noframes" -> { last-start := Just(name); tag-next-state := SRAWTEXT }
        "script" -> { last-start := Just(name); tag-next-state := SScriptData }
        "plaintext" -> { last-start := Just(name); tag-next-state := SPlaintext }
        _ -> ()
    if cur-is-end then
      emit-token(TokEndTag(name))
    else
      emit-token(TokStartTag(name, cur-attrs.reverse, cur-selfclosing))
    cur-is-end := False
    cur-name := Nil
    cur-attrs := Nil
    cur-selfclosing := False
    pending-endtag-solidus := False

  fun is-appropriate-end-tag(ls: maybe<string>, tmp: list<char>) : <div,exn> bool
    match ls
      Nothing -> False
      Just(last0) ->
        {
          val want = lower-ascii-string(last0.trim)
          val got = string/listchar/string(tmp.reverse)
          got != "" && got == want
        }

  fun emit-temp-as-text()
    val tag = string/listchar/string(temp-buffer.reverse)
    val seq = "</".list ++ tag.list
    text-acc := seq.reverse ++ text-acc
    temp-buffer := Nil

  fun emit-doctype()
    val name = string/listchar/string(doctype-name.reverse).trim
    emit-token(TokDoctype(name, doctype-public, doctype-system, doctype-force))
    doctype-name := Nil
    doctype-public := Nothing
    doctype-system := Nothing
    doctype-force := False
    doctype-id-acc := Nil
    doctype-saw-ws := False

  fun map-initial(s: tokenizer-state) : st
    match s
      Data -> SData
      PLAINTEXT -> SPlaintext
      RCDATA -> SRCDATA
      RAWTEXT -> SRAWTEXT
      ScriptData -> SScriptData
      CDATASection -> SCDataSection

  var state := map-initial(initial)
  var i := 0

  fun reconsume(prev: st)
    state := prev
    i := i - 1

  while(fn(){ i < cs.length }, fn(){
    cur-pos := i
    val c = cs[i]
    match state
      SData ->
        if c == '<' then
          state := STagOpen
        elif c == '&' then
          val (consumed, repl, refErrs) = consume-char-ref(cs, i, False)
          add-ref-errs(i + consumed - 1, refErrs)
          match repl
            Nothing -> text-acc := Cons('&', text-acc)
            Just(s) -> text-acc := s.list.reverse ++ text-acc
          i := i + consumed - 1
        elif c == '\u0000' then
          { add-err("unexpected-null-character", i); text-acc := Cons('\u0000', text-acc) }
        else
          text-acc := Cons(repl-nul(c), text-acc)
      SRCDATA ->
        if c == '&' then
          val (consumed, repl, refErrs) = consume-char-ref(cs, i, False)
          add-ref-errs(i + consumed - 1, refErrs)
          match repl
            Nothing -> text-acc := Cons('&', text-acc)
            Just(s) -> text-acc := s.list.reverse ++ text-acc
          i := i + consumed - 1
        elif c == '<' then
          state := SRCDATALessThanSign
        else
          text-acc := Cons(repl-nul(c), text-acc)
      SRAWTEXT ->
        if c == '<' then
          state := SRAWTEXTLessThanSign
        else
          text-acc := Cons(repl-nul(c), text-acc)
      SScriptData ->
        if c == '<' then
          state := SScriptDataLessThanSign
        else
          text-acc := Cons(repl-nul(c), text-acc)
      SRCDATALessThanSign ->
        if c == '/' then
          { temp-buffer := Nil; cur-is-end := True; cur-name := Nil; state := SRCDATAEndTagOpen }
        else
          { text-acc := Cons('<', text-acc); reconsume(SRCDATA) }
      SRCDATAEndTagOpen ->
        if is-ascii-alpha(c) then
          { temp-buffer := Cons(lower-ascii(c), Nil); cur-name := Cons(lower-ascii(c), Nil); cur-is-end := True; state := SRCDATAEndTagName }
        else
          { text-acc := Cons('<', text-acc); text-acc := Cons('/', text-acc); reconsume(SRCDATA) }
      SRCDATAEndTagName ->
        if is-ascii-alnum(c) then
          { temp-buffer := Cons(lower-ascii(c), temp-buffer); cur-name := Cons(lower-ascii(c), cur-name) }
        elif (is-ws(c) || c == '/' || c == '>') then
          if is-appropriate-end-tag(last-start, temp-buffer) then
            if c == '>' then
              { emit-token(TokEndTag(string/listchar/string(temp-buffer.reverse))); temp-buffer := Nil; state := SData }
            elif c == '/' then
              { pending-endtag-solidus := True; endtag-solidus-saw-non-gt := False; state := SSelfClosingStartTag }
            else
              { state := SBeforeAttrName }
          else
            { emit-temp-as-text(); reconsume(SRCDATA) }
        else
          { emit-temp-as-text(); reconsume(SRCDATA) }
      SRAWTEXTLessThanSign ->
        if c == '/' then
          { temp-buffer := Nil; cur-is-end := True; cur-name := Nil; state := SRAWTEXTEndTagOpen }
        else
          { text-acc := Cons('<', text-acc); reconsume(SRAWTEXT) }
      SRAWTEXTEndTagOpen ->
        if is-ascii-alpha(c) then
          { temp-buffer := Cons(lower-ascii(c), Nil); cur-name := Cons(lower-ascii(c), Nil); cur-is-end := True; state := SRAWTEXTEndTagName }
        else
          { text-acc := Cons('<', text-acc); text-acc := Cons('/', text-acc); reconsume(SRAWTEXT) }
      SRAWTEXTEndTagName ->
        if is-ascii-alnum(c) then
          { temp-buffer := Cons(lower-ascii(c), temp-buffer); cur-name := Cons(lower-ascii(c), cur-name) }
        elif (is-ws(c) || c == '/' || c == '>') then
          if is-appropriate-end-tag(last-start, temp-buffer) then
            if c == '>' then
              { emit-token(TokEndTag(string/listchar/string(temp-buffer.reverse))); temp-buffer := Nil; state := SData }
            elif c == '/' then
              { pending-endtag-solidus := True; endtag-solidus-saw-non-gt := False; state := SSelfClosingStartTag }
            else
              { state := SBeforeAttrName }
          else
            { emit-temp-as-text(); reconsume(SRAWTEXT) }
        else
          { emit-temp-as-text(); reconsume(SRAWTEXT) }
      SScriptDataLessThanSign ->
        if c == '/' then
          { temp-buffer := Nil; cur-is-end := True; cur-name := Nil; state := SScriptDataEndTagOpen }
        elif c == '!' then
          { text-acc := Cons('<', text-acc); text-acc := Cons('!', text-acc); state := SScriptDataEscapeStart }
        else
          { text-acc := Cons('<', text-acc); reconsume(SScriptData) }
      SScriptDataEndTagOpen ->
        if is-ascii-alpha(c) then
          { temp-buffer := Cons(lower-ascii(c), Nil); cur-name := Cons(lower-ascii(c), Nil); cur-is-end := True; state := SScriptDataEndTagName }
        else
          { text-acc := Cons('<', text-acc); text-acc := Cons('/', text-acc); reconsume(SScriptData) }
      SScriptDataEndTagName ->
        if is-ascii-alnum(c) then
          { temp-buffer := Cons(lower-ascii(c), temp-buffer); cur-name := Cons(lower-ascii(c), cur-name) }
        elif (is-ws(c) || c == '/' || c == '>') then
          if is-appropriate-end-tag(last-start, temp-buffer) then
            if c == '>' then
              { emit-token(TokEndTag(string/listchar/string(temp-buffer.reverse))); temp-buffer := Nil; state := SData }
            elif c == '/' then
              { pending-endtag-solidus := True; endtag-solidus-saw-non-gt := False; state := SSelfClosingStartTag }
            else
              { state := SBeforeAttrName }
          else
            { emit-temp-as-text(); reconsume(SScriptData) }
        else
          { emit-temp-as-text(); reconsume(SScriptData) }
      SScriptDataEscapeStart ->
        if c == '-' then
          { text-acc := Cons('-', text-acc); state := SScriptDataEscapeStartDash }
        else
          reconsume(SScriptData)
      SScriptDataEscapeStartDash ->
        if c == '-' then
          { text-acc := Cons('-', text-acc); state := SScriptDataEscapedDashDash }
        else
          reconsume(SScriptData)
      SScriptDataEscaped ->
        if c == '-' then
          { text-acc := Cons('-', text-acc); state := SScriptDataEscapedDash }
        elif c == '<' then
          state := SScriptDataEscapedLessThanSign
        else
          text-acc := Cons(repl-nul(c), text-acc)
      SScriptDataEscapedDash ->
        if c == '-' then
          { text-acc := Cons('-', text-acc); state := SScriptDataEscapedDashDash }
        elif c == '<' then
          state := SScriptDataEscapedLessThanSign
        else
          { text-acc := Cons(repl-nul(c), text-acc); state := SScriptDataEscaped }
      SScriptDataEscapedDashDash ->
        if c == '-' then
          text-acc := Cons('-', text-acc)
        elif c == '<' then
          state := SScriptDataEscapedLessThanSign
        elif c == '>' then
          { text-acc := Cons('>', text-acc); state := SScriptData }
        else
          { text-acc := Cons(repl-nul(c), text-acc); state := SScriptDataEscaped }
      SScriptDataEscapedLessThanSign ->
        if c == '/' then
          { temp-buffer := Nil; cur-is-end := True; cur-name := Nil; state := SScriptDataEscapedEndTagOpen }
        elif is-ascii-alpha(c) then
          // Emit "<" + c and enter the double-escape start scanner.
          {
            temp-buffer := Cons(lower-ascii(c), Nil)
            text-acc := Cons('<', text-acc)
            text-acc := Cons(repl-nul(c), text-acc)
            state := SScriptDataDoubleEscapeStart
          }
        else
          { text-acc := Cons('<', text-acc); reconsume(SScriptDataEscaped) }
      SScriptDataEscapedEndTagOpen ->
        if is-ascii-alpha(c) then
          { temp-buffer := Cons(lower-ascii(c), Nil); cur-name := Cons(lower-ascii(c), Nil); cur-is-end := True; state := SScriptDataEscapedEndTagName }
        else
          { text-acc := Cons('<', text-acc); text-acc := Cons('/', text-acc); reconsume(SScriptDataEscaped) }
      SScriptDataEscapedEndTagName ->
        if is-ascii-alnum(c) then
          { temp-buffer := Cons(lower-ascii(c), temp-buffer); cur-name := Cons(lower-ascii(c), cur-name) }
        elif (is-ws(c) || c == '/' || c == '>') then
          if is-appropriate-end-tag(last-start, temp-buffer) then
            if c == '>' then
              { emit-token(TokEndTag(string/listchar/string(temp-buffer.reverse))); temp-buffer := Nil; state := SData }
            elif c == '/' then
              { pending-endtag-solidus := True; endtag-solidus-saw-non-gt := False; state := SSelfClosingStartTag }
            else
              { state := SBeforeAttrName }
          else
            { emit-temp-as-text(); reconsume(SScriptDataEscaped) }
        else
          { emit-temp-as-text(); reconsume(SScriptDataEscaped) }
      SScriptDataDoubleEscapeStart ->
        if is-ascii-alnum(c) then
          { temp-buffer := Cons(lower-ascii(c), temp-buffer); text-acc := Cons(repl-nul(c), text-acc) }
        elif (is-ws(c) || c == '/' || c == '>') then
          {
            val name = string/listchar/string(temp-buffer.reverse)
            text-acc := Cons(repl-nul(c), text-acc)
            state := (if name == "script" then SScriptDataDoubleEscaped else SScriptDataEscaped)
          }
        else
          reconsume(SScriptDataEscaped)
      SScriptDataDoubleEscaped ->
        if c == '-' then
          { text-acc := Cons('-', text-acc); state := SScriptDataDoubleEscapedDash }
        elif c == '<' then
          state := SScriptDataDoubleEscapedLessThanSign
        else
          text-acc := Cons(repl-nul(c), text-acc)
      SScriptDataDoubleEscapedDash ->
        if c == '-' then
          { text-acc := Cons('-', text-acc); state := SScriptDataDoubleEscapedDashDash }
        elif c == '<' then
          state := SScriptDataDoubleEscapedLessThanSign
        else
          { text-acc := Cons(repl-nul(c), text-acc); state := SScriptDataDoubleEscaped }
      SScriptDataDoubleEscapedDashDash ->
        if c == '-' then
          text-acc := Cons('-', text-acc)
        elif c == '<' then
          state := SScriptDataDoubleEscapedLessThanSign
        elif c == '>' then
          { text-acc := Cons('>', text-acc); state := SScriptData }
        else
          { text-acc := Cons(repl-nul(c), text-acc); state := SScriptDataDoubleEscaped }
      SScriptDataDoubleEscapedLessThanSign ->
        if c == '/' then
          { temp-buffer := Nil; text-acc := Cons('<', text-acc); text-acc := Cons('/', text-acc); state := SScriptDataDoubleEscapeEnd }
        else
          { text-acc := Cons('<', text-acc); reconsume(SScriptDataDoubleEscaped) }
      SScriptDataDoubleEscapeEnd ->
        if is-ascii-alnum(c) then
          { temp-buffer := Cons(lower-ascii(c), temp-buffer); text-acc := Cons(repl-nul(c), text-acc) }
        elif (is-ws(c) || c == '/' || c == '>') then
          {
            val name = string/listchar/string(temp-buffer.reverse)
            text-acc := Cons(repl-nul(c), text-acc)
            state := (if name == "script" then SScriptDataEscaped else SScriptDataDoubleEscaped)
          }
        else
          reconsume(SScriptDataDoubleEscaped)
      SPlaintext ->
        text-acc := Cons(repl-nul(c), text-acc)
      SCDataSection ->
        if (c == ']' && i + 2 < cs.length && cs[i + 1] == ']' && cs[i + 2] == '>') then
          { state := SData; i := i + 2 }
        else
          text-acc := Cons(c, text-acc)
      STagOpen ->
        if c == '/' then
          cur-is-end := True
          cur-name := Nil
          state := SEndTagOpen
        elif c == '!' then
          state := SMarkupDeclOpen
        elif c == '?' then
          {
            // Bogus comment (e.g. "<?...").
            // html5lib counts both a legacy and a modern error here.
            add-err("expected-tag-name-but-got-question-mark", i)
            add-err("unexpected-question-mark-instead-of-tag-name", i)
            comment-acc := Nil
            state := SBogusComment
            reconsume(SBogusComment)
          }
        elif is-ascii-alpha(c) then
          cur-is-end := False
          cur-name := Cons(lower-ascii(c), Nil)
          cur-attrs := Nil
          cur-selfclosing := False
          state := STagName
        else
          // Not a tag; emit '<' and reconsume.
          text-acc := Cons('<', text-acc)
          reconsume(SData)
      SMarkupDeclOpen ->
        if (c == '-' && i + 1 < cs.length && cs[i + 1] == '-' ) then
          // Consume "<!--"
          comment-acc := Nil
          state := SCommentStart
          i := i + 1
        elif starts-with-ci(cs, i, "DOCTYPE") then
          // Consume "<!DOCTYPE"
          doctype-name := Nil
          doctype-public := Nothing
          doctype-system := Nothing
          doctype-force := False
          doctype-id-acc := Nil
          doctype-saw-ws := False
          state := SBeforeDoctypeName
          i := i + 6
        else
          // Not a known declaration; parse as bogus comment.
          // html5lib counts both a legacy and a modern error here.
          add-err("expected-dashes-or-doctype", i)
          add-err("incorrectly-opened-comment", i)
          comment-acc := Nil
          state := SBogusComment
          reconsume(SBogusComment)
      SCommentStart ->
        if c == '-' then
          state := SCommentStartDash
        elif c == '>' then
          {
            // html5lib counts both a legacy and a modern error here.
            add-err("incorrect-comment", i)
            add-err("abrupt-closing-of-empty-comment", i)
            emit-token(TokComment(""))
            state := SData
          }
        else
          { comment-acc := Cons(repl-nul(c), comment-acc); state := SComment }
      SCommentStartDash ->
        if c == '-' then
          state := SCommentEnd
        elif c == '>' then
          {
            // html5lib counts both a legacy and a modern error here.
            add-err("incorrect-comment", i)
            add-err("abrupt-closing-of-empty-comment", i)
            emit-token(TokComment(""))
            state := SData
          }
        else
          { comment-acc := Cons('-', comment-acc); comment-acc := Cons(repl-nul(c), comment-acc); state := SComment }
      SComment ->
        if c == '-' then
          state := SCommentEndDash
        elif c == '<' then
          state := SCommentLessThanSign
        else
          comment-acc := Cons(repl-nul(c), comment-acc)
      SCommentLessThanSign ->
        if c == '!' then
          state := SCommentLessThanSignBang
        elif c == '<' then
          // The '<' was literal; keep it and stay in this state.
          comment-acc := Cons('<', comment-acc)
        else
          { comment-acc := Cons('<', comment-acc); reconsume(SComment) }
      SCommentLessThanSignBang ->
        // We've seen "<!" inside a comment; treat it as literal "<!" unless we
        // complete a nested-comment sequence.
        comment-acc := Cons('<', comment-acc)
        comment-acc := Cons('!', comment-acc)
        if c == '-' then
          state := SCommentLessThanSignBangDash
        else
          reconsume(SComment)
      SCommentLessThanSignBangDash ->
        if c == '-' then
          state := SCommentLessThanSignBangDashDash
        else
          { comment-acc := Cons('-', comment-acc); reconsume(SComment) }
      SCommentLessThanSignBangDashDash ->
        if c == '>' then
          { add-err("nested-comment", i); state := SCommentEnd }
        else
          {
            comment-acc := Cons('-', comment-acc)
            comment-acc := Cons('-', comment-acc)
            reconsume(SComment)
          }
      SCommentEndDash ->
        if c == '-' then
          state := SCommentEnd
        else
          { comment-acc := Cons('-', comment-acc); comment-acc := Cons(repl-nul(c), comment-acc); state := SComment }
      SCommentEnd ->
        if c == '>' then
          { emit-token(TokComment(string/listchar/string(comment-acc.reverse))); state := SData }
        elif c == '!' then
          state := SCommentEndBang
        elif c == '-' then
          comment-acc := Cons('-', comment-acc)
        else
          {
            // "--" was part of the comment; emit and continue.
            comment-acc := Cons('-', comment-acc)
            comment-acc := Cons('-', comment-acc)
            comment-acc := Cons(repl-nul(c), comment-acc)
            state := SComment
          }
      SCommentEndBang ->
        if c == '>' then
          {
            // html5lib counts both a legacy and a modern error here.
            add-err("unexpected-bang-after-double-dash-in-comment", i)
            add-err("incorrectly-closed-comment", i)
            emit-token(TokComment(string/listchar/string(comment-acc.reverse)))
            state := SData
          }
        elif c == '-' then
          { comment-acc := Cons('-', comment-acc); comment-acc := Cons('-', comment-acc); comment-acc := Cons('!', comment-acc); state := SCommentEndDash }
        else
          { comment-acc := Cons('-', comment-acc); comment-acc := Cons('-', comment-acc); comment-acc := Cons('!', comment-acc); comment-acc := Cons(repl-nul(c), comment-acc); state := SComment }
      SBogusComment ->
        if c == '>' then
          { emit-token(TokComment(string/listchar/string(comment-acc.reverse))); state := SData }
        else
          comment-acc := Cons(repl-nul(c), comment-acc)
      SBeforeDoctypeName ->
        if is-ws(c) then
          doctype-saw-ws := True
        elif c == '>' then
          {
            // html5lib counts both a legacy and a modern error here.
            add-err("expected-doctype-name-but-got-right-bracket", i)
            add-err("missing-doctype-name", i)
            doctype-force := True
            emit-doctype()
            state := SData
          }
        else
          if !doctype-saw-ws then
            {
              // html5lib counts both a legacy and a modern error here.
              add-err("need-space-after-doctype", i)
              add-err("missing-whitespace-before-doctype-name", i)
            }
          doctype-name := Cons(repl-nul(lower-ascii(c)), Nil)
          state := SDoctypeName
      SDoctypeName ->
        if c == '>' then
          emit-doctype()
          state := SData
        elif is-ws(c) then
          state := SAfterDoctypeName
        else
          doctype-name := Cons(repl-nul(lower-ascii(c)), doctype-name)
      SAfterDoctypeName ->
        if is-ws(c) then
          ()
        elif c == '>' then
          emit-doctype()
          state := SData
        elif starts-with-ci(cs, i, "PUBLIC") then
          { state := SAfterDoctypePublicKeyword; i := i + 5 }
        elif starts-with-ci(cs, i, "SYSTEM") then
          { state := SAfterDoctypeSystemKeyword; i := i + 5 }
        else
          { doctype-force := True; state := SBogusDoctype }
      SAfterDoctypePublicKeyword ->
        if is-ws(c) then
          state := SBeforeDoctypePublicId
        elif c == '"' then
          { doctype-id-acc := Nil; state := SDoctypePublicIdDQ }
        elif c == '\'' then
          { doctype-id-acc := Nil; state := SDoctypePublicIdSQ }
        elif c == '>' then
          { doctype-force := True; emit-doctype(); state := SData }
        else
          { doctype-force := True; state := SBogusDoctype }
      SBeforeDoctypePublicId ->
        if is-ws(c) then
          ()
        elif c == '"' then
          { doctype-id-acc := Nil; state := SDoctypePublicIdDQ }
        elif c == '\'' then
          { doctype-id-acc := Nil; state := SDoctypePublicIdSQ }
        elif c == '>' then
          { doctype-force := True; emit-doctype(); state := SData }
        else
          { doctype-force := True; state := SBogusDoctype }
      SDoctypePublicIdDQ ->
        if c == '"' then
          { doctype-public := Just(string/listchar/string(doctype-id-acc.reverse)); doctype-id-acc := Nil; state := SAfterDoctypePublicId }
        elif c == '>' then
          { doctype-force := True; doctype-public := Just(string/listchar/string(doctype-id-acc.reverse)); emit-doctype(); state := SData }
        else
          doctype-id-acc := Cons(repl-nul(c), doctype-id-acc)
      SDoctypePublicIdSQ ->
        if c == '\'' then
          { doctype-public := Just(string/listchar/string(doctype-id-acc.reverse)); doctype-id-acc := Nil; state := SAfterDoctypePublicId }
        elif c == '>' then
          { doctype-force := True; doctype-public := Just(string/listchar/string(doctype-id-acc.reverse)); emit-doctype(); state := SData }
        else
          doctype-id-acc := Cons(repl-nul(c), doctype-id-acc)
      SAfterDoctypePublicId ->
        if is-ws(c) then
          state := SBetweenDoctypePublicAndSystemId
        elif c == '>' then
          { emit-doctype(); state := SData }
        elif c == '"' then
          { doctype-id-acc := Nil; state := SDoctypeSystemIdDQ }
        elif c == '\'' then
          { doctype-id-acc := Nil; state := SDoctypeSystemIdSQ }
        else
          { doctype-force := True; state := SBogusDoctype }
      SBetweenDoctypePublicAndSystemId ->
        if is-ws(c) then
          ()
        elif c == '>' then
          { emit-doctype(); state := SData }
        elif c == '"' then
          { doctype-id-acc := Nil; state := SDoctypeSystemIdDQ }
        elif c == '\'' then
          { doctype-id-acc := Nil; state := SDoctypeSystemIdSQ }
        else
          { doctype-force := True; state := SBogusDoctype }
      SAfterDoctypeSystemKeyword ->
        if is-ws(c) then
          state := SBeforeDoctypeSystemId
        elif c == '"' then
          { doctype-id-acc := Nil; state := SDoctypeSystemIdDQ }
        elif c == '\'' then
          { doctype-id-acc := Nil; state := SDoctypeSystemIdSQ }
        elif c == '>' then
          { doctype-force := True; emit-doctype(); state := SData }
        else
          { doctype-force := True; state := SBogusDoctype }
      SBeforeDoctypeSystemId ->
        if is-ws(c) then
          ()
        elif c == '"' then
          { doctype-id-acc := Nil; state := SDoctypeSystemIdDQ }
        elif c == '\'' then
          { doctype-id-acc := Nil; state := SDoctypeSystemIdSQ }
        elif c == '>' then
          { doctype-force := True; emit-doctype(); state := SData }
        else
          { doctype-force := True; state := SBogusDoctype }
      SDoctypeSystemIdDQ ->
        if c == '"' then
          { doctype-system := Just(string/listchar/string(doctype-id-acc.reverse)); doctype-id-acc := Nil; state := SAfterDoctypeSystemId }
        elif c == '>' then
          { doctype-force := True; doctype-system := Just(string/listchar/string(doctype-id-acc.reverse)); emit-doctype(); state := SData }
        else
          doctype-id-acc := Cons(repl-nul(c), doctype-id-acc)
      SDoctypeSystemIdSQ ->
        if c == '\'' then
          { doctype-system := Just(string/listchar/string(doctype-id-acc.reverse)); doctype-id-acc := Nil; state := SAfterDoctypeSystemId }
        elif c == '>' then
          { doctype-force := True; doctype-system := Just(string/listchar/string(doctype-id-acc.reverse)); emit-doctype(); state := SData }
        else
          doctype-id-acc := Cons(repl-nul(c), doctype-id-acc)
      SAfterDoctypeSystemId ->
        if is-ws(c) then
          ()
        elif c == '>' then
          { emit-doctype(); state := SData }
        else
          if c == '\u0000' then
            { state := SBogusDoctype; reconsume(SBogusDoctype) }
          else
            state := SBogusDoctype
      SBogusDoctype ->
        if c == '>' then
          { doctype-force := True; emit-doctype(); state := SData }
        elif c == '\u0000' then
          {
            // html5lib treats NUL in bogus-doctype as ending the declaration without forcing quirks.
            add-err("unexpected-null-character", i)
            emit-doctype()
            state := SData
          }
        else
          ()
      SEndTagOpen ->
        if c == '>' then
          { add-err("missing-end-tag-name", i); state := SData }
        elif is-ascii-alpha(c) then
          cur-name := Cons(repl-nul(lower-ascii(c)), Nil)
          cur-attrs := Nil
          cur-selfclosing := False
          state := STagName
        else
          // Parse as bogus comment.
          add-err("invalid-first-character-of-tag-name", i)
          comment-acc := Nil
          state := SBogusComment
          reconsume(SBogusComment)
      STagName ->
        if c == '>' then
          { finish-tag(); state := tag-next-state }
        elif c == '/' then
          if cur-is-end then
            { pending-endtag-solidus := True; endtag-solidus-saw-non-gt := False; state := SSelfClosingStartTag }
          else
            state := SSelfClosingStartTag
        elif is-ws(c) then
          state := SBeforeAttrName
        else
          cur-name := Cons(repl-nul(lower-ascii(c)), cur-name)
      SBeforeAttrName ->
        if c == '>' then
          { finish-tag(); state := tag-next-state }
        elif c == '/' then
          state := SSelfClosingStartTag
        elif is-ws(c) then
          ()
        else
          if cur-is-end && !endtag-attr-error-emitted && !endtag-solidus-saw-non-gt then
            { add-err("attributes-in-end-tag", i); add-err("end-tag-with-attributes", i); endtag-attr-error-emitted := True }
          in-attr := True
          cur-attr-name := Cons(repl-nul(lower-ascii(c)), Nil)
          cur-attr-value := Nil
          state := SAttrName
      SAttrName ->
        if c == '=' then
          state := SBeforeAttrValue
        elif is-ws(c) then
          finish-attr()
          state := SAfterAttrName
        elif c == '/' then
          finish-attr()
          state := SSelfClosingStartTag
        elif c == '>' then
          { finish-tag(); state := tag-next-state }
        else
          cur-attr-name := Cons(repl-nul(lower-ascii(c)), cur-attr-name)
      SAfterAttrName ->
        if c == '=' then
          // Start value for previous attr; but we already finished it. Ignore.
          state := SBeforeAttrValue
        elif c == '>' then
          { finish-tag(); state := tag-next-state }
        elif c == '/' then
          state := SSelfClosingStartTag
        elif is-ws(c) then
          ()
        else
          if cur-is-end && !endtag-attr-error-emitted && !endtag-solidus-saw-non-gt then
            { add-err("attributes-in-end-tag", i); add-err("end-tag-with-attributes", i); endtag-attr-error-emitted := True }
          in-attr := True
          cur-attr-name := Cons(repl-nul(lower-ascii(c)), Nil)
          cur-attr-value := Nil
          state := SAttrName
      SBeforeAttrValue ->
        if c == ' ' || c == '\n' || c == '\t' || c == '\r' then
          ()
        elif c == '\"' then
          state := SAttrValueDQ
        elif c == '\'' then
          state := SAttrValueSQ
        elif c == '>' then
          { finish-tag(); state := tag-next-state }
        else
          cur-attr-value := Cons(repl-nul(c), Nil)
          state := SAttrValueUQ
      SAttrValueDQ ->
        if c == '\"' then
          finish-attr()
          state := SAfterAttrValueQ
        elif c == '&' then
          val (consumed, repl, refErrs) = consume-char-ref(cs, i, True)
          add-ref-errs(i + consumed - 1, refErrs)
          match repl
            Nothing -> cur-attr-value := Cons('&', cur-attr-value)
            Just(s) -> cur-attr-value := s.list.reverse ++ cur-attr-value
          i := i + consumed - 1
        else
          cur-attr-value := Cons(repl-nul(c), cur-attr-value)
      SAttrValueSQ ->
        if c == '\'' then
          finish-attr()
          state := SAfterAttrValueQ
        elif c == '&' then
          val (consumed, repl, refErrs) = consume-char-ref(cs, i, True)
          add-ref-errs(i + consumed - 1, refErrs)
          match repl
            Nothing -> cur-attr-value := Cons('&', cur-attr-value)
            Just(s) -> cur-attr-value := s.list.reverse ++ cur-attr-value
          i := i + consumed - 1
        else
          cur-attr-value := Cons(repl-nul(c), cur-attr-value)
      SAttrValueUQ ->
        if c == ' ' || c == '\n' || c == '\t' || c == '\r' then
          finish-attr()
          state := SBeforeAttrName
        elif c == '>' then
          { finish-tag(); state := tag-next-state }
        elif c == '&' then
          val (consumed, repl, refErrs) = consume-char-ref(cs, i, True)
          add-ref-errs(i + consumed - 1, refErrs)
          match repl
            Nothing -> cur-attr-value := Cons('&', cur-attr-value)
            Just(s) -> cur-attr-value := s.list.reverse ++ cur-attr-value
          i := i + consumed - 1
        else
          cur-attr-value := Cons(repl-nul(c), cur-attr-value)
      SAfterAttrValueQ ->
        if c == ' ' || c == '\n' || c == '\t' || c == '\r' then
          state := SBeforeAttrName
        elif c == '/' then
          state := SSelfClosingStartTag
        elif c == '>' then
          { finish-tag(); state := tag-next-state }
        else
          reconsume(SBeforeAttrName)
      SSelfClosingStartTag ->
        if c == '>' then
          {
            cur-selfclosing := True
            if cur-is-end && pending-endtag-solidus then
              {
                if !endtag-solidus-saw-non-gt then
                  { add-err("self-closing-flag-on-end-tag", i); add-err("end-tag-with-trailing-solidus", i) }
                pending-endtag-solidus := False
              }
            finish-tag()
            state := tag-next-state
          }
        else
          if cur-is-end && pending-endtag-solidus then
            { endtag-solidus-saw-non-gt := True; add-err("unexpected-character-after-solidus-in-tag", i); add-err("unexpected-solidus-in-tag", i); pending-endtag-solidus := False }
          reconsume(SBeforeAttrName)
    i := i + 1
  })

  // EOF
  val eof-at = if cs.length > 0 then (cs.length - 1) else 0
  match state
    STagOpen -> text-acc := Cons('<', text-acc)
    SMarkupDeclOpen -> emit-token(TokComment(""))
    SRCDATALessThanSign -> text-acc := Cons('<', text-acc)
    SRAWTEXTLessThanSign -> text-acc := Cons('<', text-acc)
    SScriptDataLessThanSign -> text-acc := Cons('<', text-acc)
    SRCDATAEndTagName -> emit-temp-as-text()
    SRAWTEXTEndTagName -> emit-temp-as-text()
    SScriptDataEndTagName -> emit-temp-as-text()
    SCommentStart -> { add-eof-in-comment(eof-at); emit-token(TokComment("")) }
    SCommentStartDash -> { add-eof-in-comment(eof-at); emit-token(TokComment("")) }
    SComment -> { add-eof-in-comment(eof-at); emit-token(TokComment(string/listchar/string(comment-acc.reverse))) }
    SCommentLessThanSign ->
      { add-eof-in-comment(eof-at); comment-acc := Cons('<', comment-acc); emit-token(TokComment(string/listchar/string(comment-acc.reverse))) }
    SCommentLessThanSignBang ->
      { add-eof-in-comment(eof-at); comment-acc := Cons('<', comment-acc); comment-acc := Cons('!', comment-acc); emit-token(TokComment(string/listchar/string(comment-acc.reverse))) }
    SCommentLessThanSignBangDash ->
      { add-eof-in-comment(eof-at); comment-acc := Cons('-', comment-acc); emit-token(TokComment(string/listchar/string(comment-acc.reverse))) }
    SCommentLessThanSignBangDashDash -> { add-eof-in-comment(eof-at); emit-token(TokComment(string/listchar/string(comment-acc.reverse))) }
    SCommentEndDash -> { add-eof-in-comment(eof-at); emit-token(TokComment(string/listchar/string(comment-acc.reverse))) }
    SCommentEnd -> { add-eof-in-comment(eof-at); emit-token(TokComment(string/listchar/string(comment-acc.reverse))) }
    SCommentEndBang -> { add-eof-in-comment(eof-at); emit-token(TokComment(string/listchar/string(comment-acc.reverse))) }
    SEndTagOpen ->
      { text-acc := Cons('<', text-acc); text-acc := Cons('/', text-acc) }
    SBogusComment ->
      // Bogus comments at EOF are not counted as "eof-in-comment" by html5lib's tree fixtures.
      emit-token(TokComment(string/listchar/string(comment-acc.reverse)))
    SBeforeDoctypeName -> { doctype-force := True; emit-doctype() }
    SDoctypeName -> { doctype-force := True; emit-doctype() }
    SAfterDoctypeName -> { doctype-force := True; emit-doctype() }
    SAfterDoctypePublicKeyword -> { doctype-force := True; emit-doctype() }
    SBeforeDoctypePublicId -> { doctype-force := True; emit-doctype() }
    SDoctypePublicIdDQ -> { doctype-force := True; doctype-public := Just(string/listchar/string(doctype-id-acc.reverse)); emit-doctype() }
    SDoctypePublicIdSQ -> { doctype-force := True; doctype-public := Just(string/listchar/string(doctype-id-acc.reverse)); emit-doctype() }
    SAfterDoctypePublicId -> { doctype-force := True; emit-doctype() }
    SBetweenDoctypePublicAndSystemId -> { doctype-force := True; emit-doctype() }
    SAfterDoctypeSystemKeyword -> { doctype-force := True; emit-doctype() }
    SBeforeDoctypeSystemId -> { doctype-force := True; emit-doctype() }
    SDoctypeSystemIdDQ -> { doctype-force := True; doctype-system := Just(string/listchar/string(doctype-id-acc.reverse)); emit-doctype() }
    SDoctypeSystemIdSQ -> { doctype-force := True; doctype-system := Just(string/listchar/string(doctype-id-acc.reverse)); emit-doctype() }
    SAfterDoctypeSystemId -> { doctype-force := True; emit-doctype() }
    SBogusDoctype -> { doctype-force := True; emit-doctype() }
    _ -> ()
  flush-text()
  out := Cons(TokEOF, out)
  (out.reverse, errs.reverse)

pub fun tokenize(input: string, initial: tokenizer-state = Data, lastStartTag: maybe<string> = Nothing)
  : <div,exn> (tokens: list<token>, errors: list<parseerror>)
  tokenize-internal(input, initial, lastStartTag, False)

pub fun tokenize-for-parse(input: string, initial: tokenizer-state = Data, lastStartTag: maybe<string> = Nothing)
  : <div,exn> (tokens: list<token>, errors: list<parseerror>)
  tokenize-internal(input, initial, lastStartTag, True)

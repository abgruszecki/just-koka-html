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
  SComment
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
    elif c0 == '\u0000' then
      out := Cons('\uFFFD', out)
      i := i + 1
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

fun consume-char-ref(cs: vector<char>, pos: int) : <div,exn> (consumed: int, replacement: maybe<string>)
  // `pos` is the index of '&'.
  val len = cs.length
  val next = pos + 1
  if next >= len then (1, Nothing) else
    val c1 = cs[next]
    if c1 == '#' then
      // Numeric character reference.
      val n2 = next + 1
      if n2 >= len then (1, Nothing) else
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
        if j == digitsStart then (1, Nothing) else
          val hasSemi = (j < len && cs[j] == ';')
          val end = j
          val code = parse-uint(cs, digitsStart, end, if isHex then 16 else 10)
          val safe = if (code <= 0 || code > 0x10FFFF) then 0xFFFD else code
          val s = char/string(safe.char)
          val consumed = (if hasSemi then (j - pos + 1) else (j - pos))
          (consumed, Just(s))
    else
      // Named character reference: ASCII alnum only.
      var j := next
      while(fn(){ j < len && is-ascii-alnum(cs[j]) }, fn(){ j := j + 1 })
      if j == next then (1, Nothing) else
        val hasSemi = (j < len && cs[j] == ';')
        // Prefer semicolon-terminated form.
        if hasSemi then
          val key = slice-string(cs, next, j + 1)
          match entities/lookup(key)
            Just(v) -> (j - pos + 1, Just(v))
            Nothing -> (1, Nothing)
        else
          val key = slice-string(cs, next, j)
          // Legacy (no semicolon) only if next char isn't alnum or '='.
          val following = if j < len then cs[j] else '\u0000'
          if (j < len && (is-ascii-alnum(following) || following == '=')) then
            (1, Nothing)
          else
            match entities/lookup(key)
              Just(v) -> (j - pos, Just(v))
              Nothing -> (1, Nothing)

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

// M1: a pragmatic subset tokenizer (enough to start enabling non-entity tag/text tests).
pub fun tokenize(input: string, initial: tokenizer-state = Data, lastStartTag: maybe<string> = Nothing)
  : <div,exn> (tokens: list<token>, errors: list<parseerror>)
  val cs = preprocess(input)

  // Token under construction
  var cur-is-end := False
  var cur-name : list<char> := Nil
  var cur-attrs : list<attr> := Nil
  var cur-selfclosing := False
  var cur-attr-name : list<char> := Nil
  var cur-attr-value : list<char> := Nil
  var in-attr := False

  // Output
  var out : list<token> := Nil
  var text-acc : list<char> := Nil
  var comment-acc : list<char> := Nil
  var doctype-name : list<char> := Nil
  var doctype-public : maybe<string> := Nothing
  var doctype-system : maybe<string> := Nothing
  var doctype-force := False
  var doctype-id-acc : list<char> := Nil
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
        cur-attrs := Cons(Attr(an, v), cur-attrs)
      cur-attr-name := Nil
      cur-attr-value := Nil
      in-attr := False

  fun finish-tag()
    finish-attr()
    val name = string/listchar/string(cur-name.reverse).trim
    if cur-is-end then
      emit-token(TokEndTag(name))
    else
      emit-token(TokStartTag(name, cur-attrs.reverse, cur-selfclosing))
    cur-is-end := False
    cur-name := Nil
    cur-attrs := Nil
    cur-selfclosing := False

  fun emit-doctype()
    val name = string/listchar/string(doctype-name.reverse)
    emit-token(TokDoctype(name, doctype-public, doctype-system, doctype-force))
    doctype-name := Nil
    doctype-public := Nothing
    doctype-system := Nothing
    doctype-force := False
    doctype-id-acc := Nil

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
    val c = cs[i]
    match state
      SData ->
        if c == '<' then
          state := STagOpen
        elif c == '&' then
          val (consumed, repl) = consume-char-ref(cs, i)
          match repl
            Nothing -> text-acc := Cons('&', text-acc)
            Just(s) -> text-acc := s.list.reverse ++ text-acc
          i := i + consumed - 1
        else
          text-acc := Cons(c, text-acc)
      SRCDATA ->
        if c == '&' then
          val (consumed, repl) = consume-char-ref(cs, i)
          match repl
            Nothing -> text-acc := Cons('&', text-acc)
            Just(s) -> text-acc := s.list.reverse ++ text-acc
          i := i + consumed - 1
        elif c == '<' then
          val (consumed, tag) = consume-rawtext-endtag(cs, i, lastStartTag)
          match tag
            Nothing -> text-acc := Cons('<', text-acc)
            Just(name) ->
              {
                emit-token(TokEndTag(name))
                state := SData
                i := i + consumed - 1
              }
        else
          text-acc := Cons(c, text-acc)
      SRAWTEXT ->
        if c == '<' then
          val (consumed, tag) = consume-rawtext-endtag(cs, i, lastStartTag)
          match tag
            Nothing -> text-acc := Cons('<', text-acc)
            Just(name) ->
              {
                emit-token(TokEndTag(name))
                state := SData
                i := i + consumed - 1
              }
        else
          text-acc := Cons(c, text-acc)
      SScriptData ->
        if c == '<' then
          val (consumed, tag) = consume-rawtext-endtag(cs, i, lastStartTag)
          match tag
            Nothing -> text-acc := Cons('<', text-acc)
            Just(name) ->
              {
                emit-token(TokEndTag(name))
                state := SData
                i := i + consumed - 1
              }
        else
          text-acc := Cons(c, text-acc)
      SPlaintext ->
        text-acc := Cons(c, text-acc)
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
        if (c == '-' && i + 2 < cs.length && cs[i + 1] == '-' ) then
          // Consume "<!--"
          comment-acc := Nil
          state := SComment
          i := i + 1
        elif starts-with-ci(cs, i, "DOCTYPE") then
          // Consume "<!DOCTYPE"
          doctype-name := Nil
          doctype-public := Nothing
          doctype-system := Nothing
          doctype-force := False
          doctype-id-acc := Nil
          state := SBeforeDoctypeName
          i := i + 6
        else
          // Not a known declaration; emit "<!" and reconsume.
          text-acc := Cons('!', text-acc)
          text-acc := Cons('<', text-acc)
          reconsume(SData)
      SComment ->
        if (c == '-' && i + 2 < cs.length && cs[i + 1] == '-' && cs[i + 2] == '>') then
          emit-token(TokComment(string/listchar/string(comment-acc.reverse)))
          state := SData
          i := i + 2
        else
          comment-acc := Cons(c, comment-acc)
      SBeforeDoctypeName ->
        if is-ws(c) then
          ()
        elif c == '>' then
          doctype-force := True
          emit-doctype()
          state := SData
        else
          doctype-name := Cons(lower-ascii(c), Nil)
          state := SDoctypeName
      SDoctypeName ->
        if c == '>' then
          emit-doctype()
          state := SData
        elif is-ws(c) then
          state := SAfterDoctypeName
        else
          doctype-name := Cons(lower-ascii(c), doctype-name)
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
          doctype-id-acc := Cons(c, doctype-id-acc)
      SDoctypePublicIdSQ ->
        if c == '\'' then
          { doctype-public := Just(string/listchar/string(doctype-id-acc.reverse)); doctype-id-acc := Nil; state := SAfterDoctypePublicId }
        elif c == '>' then
          { doctype-force := True; doctype-public := Just(string/listchar/string(doctype-id-acc.reverse)); emit-doctype(); state := SData }
        else
          doctype-id-acc := Cons(c, doctype-id-acc)
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
          doctype-id-acc := Cons(c, doctype-id-acc)
      SDoctypeSystemIdSQ ->
        if c == '\'' then
          { doctype-system := Just(string/listchar/string(doctype-id-acc.reverse)); doctype-id-acc := Nil; state := SAfterDoctypeSystemId }
        elif c == '>' then
          { doctype-force := True; doctype-system := Just(string/listchar/string(doctype-id-acc.reverse)); emit-doctype(); state := SData }
        else
          doctype-id-acc := Cons(c, doctype-id-acc)
      SAfterDoctypeSystemId ->
        if is-ws(c) then
          ()
        elif c == '>' then
          { emit-doctype(); state := SData }
        else
          { doctype-force := True; state := SBogusDoctype }
      SBogusDoctype ->
        if c == '>' then
          { doctype-force := True; emit-doctype(); state := SData }
        else
          ()
      SEndTagOpen ->
        if is-ascii-alpha(c) then
          cur-name := Cons(lower-ascii(c), Nil)
          cur-attrs := Nil
          cur-selfclosing := False
          state := STagName
        else
          // Invalid end tag open; treat as text.
          text-acc := Cons('<', text-acc)
          text-acc := Cons('/', text-acc)
          reconsume(SData)
      STagName ->
        if c == '>' then
          finish-tag()
          state := SData
        elif c == '/' then
          state := SSelfClosingStartTag
        elif c == ' ' || c == '\n' || c == '\t' || c == '\r' then
          state := SBeforeAttrName
        else
          cur-name := Cons(lower-ascii(c), cur-name)
      SBeforeAttrName ->
        if c == '>' then
          finish-tag()
          state := SData
        elif c == '/' then
          state := SSelfClosingStartTag
        elif c == ' ' || c == '\n' || c == '\t' || c == '\r' then
          ()
        else
          in-attr := True
          cur-attr-name := Cons(lower-ascii(c), Nil)
          cur-attr-value := Nil
          state := SAttrName
      SAttrName ->
        if c == '=' then
          state := SBeforeAttrValue
        elif c == ' ' || c == '\n' || c == '\t' || c == '\r' then
          finish-attr()
          state := SAfterAttrName
        elif c == '/' then
          finish-attr()
          state := SSelfClosingStartTag
        elif c == '>' then
          finish-tag()
          state := SData
        else
          cur-attr-name := Cons(lower-ascii(c), cur-attr-name)
      SAfterAttrName ->
        if c == '=' then
          // Start value for previous attr; but we already finished it. Ignore.
          state := SBeforeAttrValue
        elif c == '>' then
          finish-tag()
          state := SData
        elif c == '/' then
          state := SSelfClosingStartTag
        elif c == ' ' || c == '\n' || c == '\t' || c == '\r' then
          ()
        else
          in-attr := True
          cur-attr-name := Cons(lower-ascii(c), Nil)
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
          finish-tag()
          state := SData
        else
          cur-attr-value := Cons(c, Nil)
          state := SAttrValueUQ
      SAttrValueDQ ->
        if c == '\"' then
          finish-attr()
          state := SAfterAttrValueQ
        elif c == '&' then
          val (consumed, repl) = consume-char-ref(cs, i)
          match repl
            Nothing -> cur-attr-value := Cons('&', cur-attr-value)
            Just(s) -> cur-attr-value := s.list.reverse ++ cur-attr-value
          i := i + consumed - 1
        else
          cur-attr-value := Cons(c, cur-attr-value)
      SAttrValueSQ ->
        if c == '\'' then
          finish-attr()
          state := SAfterAttrValueQ
        elif c == '&' then
          val (consumed, repl) = consume-char-ref(cs, i)
          match repl
            Nothing -> cur-attr-value := Cons('&', cur-attr-value)
            Just(s) -> cur-attr-value := s.list.reverse ++ cur-attr-value
          i := i + consumed - 1
        else
          cur-attr-value := Cons(c, cur-attr-value)
      SAttrValueUQ ->
        if c == ' ' || c == '\n' || c == '\t' || c == '\r' then
          finish-attr()
          state := SBeforeAttrName
        elif c == '>' then
          finish-tag()
          state := SData
        elif c == '&' then
          val (consumed, repl) = consume-char-ref(cs, i)
          match repl
            Nothing -> cur-attr-value := Cons('&', cur-attr-value)
            Just(s) -> cur-attr-value := s.list.reverse ++ cur-attr-value
          i := i + consumed - 1
        else
          cur-attr-value := Cons(c, cur-attr-value)
      SAfterAttrValueQ ->
        if c == ' ' || c == '\n' || c == '\t' || c == '\r' then
          state := SBeforeAttrName
        elif c == '/' then
          state := SSelfClosingStartTag
        elif c == '>' then
          finish-tag()
          state := SData
        else
          reconsume(SBeforeAttrName)
      SSelfClosingStartTag ->
        if c == '>' then
          cur-selfclosing := True
          finish-tag()
          state := SData
        else
          reconsume(SBeforeAttrName)
    i := i + 1
  })

  // EOF
  match state
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
  (out.reverse, Nil)

module html5/tokenizer

import std/core/string
import html5/dom

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

pub struct parseerror(code: string, line: int, col: int)

type st {
  SData
  STagOpen
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
}

fun is-ascii-alpha(c: char) : bool
  (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')

fun lower-ascii(c: char) : char
  if (c >= 'A' && c <= 'Z') then (c.int + 32).char else c

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

  fun map-initial(s: tokenizer-state) : st
    match s
      Data -> SData
      _ -> SData

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
        else
          text-acc := Cons(c, text-acc)
      STagOpen ->
        if c == '/' then
          cur-is-end := True
          cur-name := Nil
          state := SEndTagOpen
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
        else
          cur-attr-value := Cons(c, cur-attr-value)
      SAttrValueSQ ->
        if c == '\'' then
          finish-attr()
          state := SAfterAttrValueQ
        else
          cur-attr-value := Cons(c, cur-attr-value)
      SAttrValueUQ ->
        if c == ' ' || c == '\n' || c == '\t' || c == '\r' then
          finish-attr()
          state := SBeforeAttrName
        elif c == '>' then
          finish-tag()
          state := SData
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
  flush-text()
  out := Cons(TokEOF, out)
  (out.reverse, Nil)

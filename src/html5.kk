module html5

import std/core/string

import html5/errors
import html5/dom
import html5/tokenizer
import html5/treebuilder
import html5/serialize
import html5/encoding

pub alias parseerror = errors/parseerror

pub struct parseoptions(
  collect-errors: bool,
  strict: bool,
  scripting-enabled: bool,
  iframe-srcdoc: bool
)

pub val default-parse-options : parseoptions =
  Parseoptions(True, False, True, False)

pub struct parseresult(dom: dom, errors: list<parseerror>)

fun is-ws-only(s: string) : <div,exn> bool
  val cs = string/vector(s)
  var ok := True
  var i := 0
  while(fn(){ ok && i < cs.length }, fn(){
    val c = cs[i]
    ok := (c == ' ' || c == '\n' || c == '\t' || c == '\r' || c == '\u000c')
    i := i + 1
  })
  ok

pub fun parse(html: string, opts: parseoptions = default-parse-options) : <div,exn> parseresult
  val (tokens, errors) = tokenizer/tokenize-for-parse(html, Data, Nothing, opts.scripting-enabled)
  val (dom, treeErrs) = treebuilder/build-document(tokens, opts.scripting-enabled)

  // Tree construction tests check parse error counts; for user-facing APIs we also include
  // a "missing-doctype" error (when no leading doctype is present), with a best-effort location.
  fun saw-leading-doctype(ts: list<tokenizer/tokenloc>) : <div,exn> bool
    match ts
      Nil -> False
      Cons(Tokenloc(t, _line, _col), rest) ->
        match t
          TokDoctype(_,_,_,_) -> True
          TokComment(_) -> saw-leading-doctype(rest)
          TokCharacter(s) -> if is-ws-only(s) then saw-leading-doctype(rest) else False
          _ -> False

  fun first-token-loc(ts: list<tokenizer/tokenloc>) : (int, int)
    match ts
      Nil -> (1, 1)
      Cons(Tokenloc(_t, line, col), _rest) -> (line, col)

  val allErrors = treeErrs ++ errors
  val withMissingDoctype =
    if saw-leading-doctype(tokens) then allErrors
    else
      {
        val (line, col) = first-token-loc(tokens)
        Cons(Parseerror("missing-doctype", line, col), allErrors)
      }

  // Preserve historical ordering (tokenizer then treebuilder-ish) by stable sorting on location later (Milestone 4/cleanup).
  // For now, just return in encounter order.
  Parseresult(dom, withMissingDoctype)

pub fun parse-fragment(html: string, fragCtx: fragmentcontext, opts: parseoptions = default-parse-options) : <div,exn> parseresult
  fun lower-ascii(c: char) : char
    if (c >= 'A' && c <= 'Z') then (c.int + 32).char else c

  fun lower-ascii-string(s: string) : <div,exn> string
    val cs = string/vector(s)
    fun go(i: int, acc: list<char>) : <div,exn> list<char>
      if i >= cs.length then acc.reverse else go(i + 1, Cons(lower-ascii(cs[i]), acc))
    string/listchar/string(go(0, Nil))

  fun fragment-tokenizer-state(tag0: string) : <div,exn> tokenizer/tokenizer-state
    val tag = lower-ascii-string(tag0.trim)
    if tag == "title" || tag == "textarea" then RCDATA
    elif tag == "script" then ScriptData
    elif tag == "plaintext" then PLAINTEXT
    elif tag == "style" || tag == "xmp" || tag == "iframe" || tag == "noembed" || tag == "noframes" || tag == "noscript" then RAWTEXT
    else Data

  val init =
    match fragCtx.ns
      Html -> fragment-tokenizer-state(fragCtx.tag)
      _ -> Data
  val last =
    match init
      Data -> Nothing
      _ -> Just(lower-ascii-string(fragCtx.tag.trim))
  val (tokens, errors) = tokenizer/tokenize-for-parse(html, init, last, opts.scripting-enabled)
  val (dom, treeErrs) = treebuilder/build-fragment(tokens, fragCtx, opts.scripting-enabled)
  val allErrors = treeErrs ++ errors
  Parseresult(dom, allErrors)

pub val tokenize = tokenizer/tokenize

pub val to-test-format = serialize/to-test-format

pub val sniff-encoding = encoding/sniff-encoding

pub fun parse-bytes(bytes: vector<int>, opts: parseoptions = default-parse-options, transport-encoding: maybe<string> = Nothing)
  : <div,exn> parseresult
  val (html, _enc) = encoding/decode-html(bytes, transport-encoding)
  parse(html, opts)

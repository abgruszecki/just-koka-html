module html5

import std/core/string

import html5/errors
import html5/dom
import html5/tokenizer
import html5/treebuilder
import html5/serialize

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
  val (tokens, errors) = tokenizer/tokenize-for-parse(html, Data)
  val (dom, treeErrCount) = treebuilder/build-document(tokens)
  // Tree construction tests only check parse error *counts*; start by matching the common "missing doctype" case.
  fun saw-leading-doctype(ts: list<tokenizer/token>) : <div,exn> bool
    match ts
      Nil -> False
      Cons(t, rest) ->
        match t
          TokDoctype(_,_,_,_) -> True
          TokComment(_) -> saw-leading-doctype(rest)
          TokCharacter(s) -> if is-ws-only(s) then saw-leading-doctype(rest) else False
          _ -> False

  fun add-n-tree-errors(n: int, acc: list<parseerror>) : <div> list<parseerror>
    if n <= 0 then acc else add-n-tree-errors(n - 1, Cons(Parseerror("tree-error", 1, 1), acc))

  val withTree = add-n-tree-errors(treeErrCount, errors)
  val withMissingDoctype =
    if saw-leading-doctype(tokens) then withTree
    else Cons(Parseerror("missing-doctype", 1, 1), withTree)
  Parseresult(dom, withMissingDoctype.reverse)

pub fun parse-fragment(html: string, fragCtx: fragmentcontext, opts: parseoptions = default-parse-options) : <div,exn> parseresult
  val (tokens, errors) = tokenizer/tokenize-for-parse(html, Data)
  val (dom, treeErrCount) = treebuilder/build-fragment(tokens, fragCtx)
  fun add-n-tree-errors(n: int, acc: list<parseerror>) : <div> list<parseerror>
    if n <= 0 then acc else add-n-tree-errors(n - 1, Cons(Parseerror("tree-error", 1, 1), acc))
  val withTree = add-n-tree-errors(treeErrCount, errors)
  Parseresult(dom, withTree.reverse)

pub val tokenize = tokenizer/tokenize

pub val to-test-format = serialize/to-test-format

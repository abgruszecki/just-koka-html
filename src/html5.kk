module html5

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

pub fun parse(html: string, opts: parseoptions = default-parse-options) : <div,exn> parseresult
  val (tokens, errors) = tokenizer/tokenize(html, Data)
  val dom = treebuilder/build-document(tokens)
  Parseresult(dom, errors)

pub fun parse-fragment(html: string, fragCtx: fragmentcontext, opts: parseoptions = default-parse-options) : <div,exn> parseresult
  val (tokens, errors) = tokenizer/tokenize(html, Data)
  val dom = treebuilder/build-fragment(tokens, fragCtx)
  Parseresult(dom, errors)

pub val tokenize = tokenizer/tokenize

pub val to-test-format = serialize/to-test-format

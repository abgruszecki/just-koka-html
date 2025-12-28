module cli

import std/os/env
import std/os/file
import std/os/path
import std/os/readline
import std/core/string
import std/core/int

import html5
import html5/json
import html5/base64
import html5/tokenizer
import html5/treebuilder
import html5/dom
import html5/encoding

fun state-from-arg(s: string) : tokenizer/tokenizer-state
  match s
    "Data" -> Data
    "PLAINTEXT" -> PLAINTEXT
    "RCDATA" -> RCDATA
    "RAWTEXT" -> RAWTEXT
    "ScriptData" -> ScriptData
    "CDATASection" -> CDATASection
    _ -> Data

fun attr-dict-json(attrs: list<attr>) : <div,exn> string
  // html5lib tokenizer expects {name:value} with plain (no namespace) names.
  val pairs = attrs.map(fn(a){
    val k = json/escape-string(a.name.local)
    val v = json/escape-string(a.value)
    (k, v)
  })
  json/obj(pairs)

fun token-json(t: tokenizer/token) : <div,exn> string
  match t
    TokEOF -> json/arr([json/escape-string("EOF")])
    TokCharacter(data) ->
      json/arr([json/escape-string("Character"), json/escape-string(data)])
    TokComment(data) ->
      json/arr([json/escape-string("Comment"), json/escape-string(data)])
    TokEndTag(name) ->
      json/arr([json/escape-string("EndTag"), json/escape-string(name)])
    TokStartTag(name, attrs, selfClosing) ->
      if selfClosing then
        json/arr([json/escape-string("StartTag"), json/escape-string(name), attr-dict-json(attrs), "true"])
      else
        json/arr([json/escape-string("StartTag"), json/escape-string(name), attr-dict-json(attrs)])
    TokDoctype(name, publicId, systemId, forceQuirks) ->
      {
        val name-json = if name.trim == "" then "null" else json/escape-string(name)
        val pub-id =
          match publicId
            Nothing -> "null"
            Just(x) -> json/escape-string(x)
        val sys-id =
          match systemId
            Nothing -> "null"
            Just(x) -> json/escape-string(x)
        val quirks = if forceQuirks then "false" else "true"
        json/arr([json/escape-string("DOCTYPE"), name-json, pub-id, sys-id, quirks])
      }

fun run-tokenizer(args: list<string>) : <console,fsys,div,exn> ()
  // args: tokenizer <state> <lastStartTagOr-> <inputPath>
  val stateArg = args.drop(1).head("Data")
  val lastArg = args.drop(2).head("-")
  val pathStr = args.drop(3).head("")
  val input = read-text-file(path(pathStr))
  val last = if lastArg == "-" then Nothing else Just(lastArg)
  val (tokens, _errors) = tokenizer/tokenize(input, state-from-arg(stateArg), last)
  // Drop EOF for html5lib comparison (EOF isn't in expected outputs).
  val toks = tokens.filter(fn(t) match t { TokEOF -> False; _ -> True })
  val out = json/arr(toks.map(token-json))
  out.println

fun run-tokenizer-batch(xmlFixup: bool) : <console,div,exn> ()
  // stdin protocol:
  // - First line: integer N
  // - Per case:
  //   - Header line: "<state>\t<lastStartTagOr->\t<base64_char_len>"
  //   - Followed by as many base64 chunk lines (<= ~900 chars) as needed
  val n = readline().trim.parse-int.default(0)

  fun read-b64(remaining: int, acc: list<string>) : <console,div,exn> list<string>
    if remaining <= 0 then acc else
      val chunk = readline()
      read-b64(remaining - chunk.count, Cons(chunk, acc))

  fun go(i: int, outs: list<string>) : <console,div,exn> list<string>
    if i >= n then outs.reverse else
      val header = readline()
      val parts = string/sep/split(header, "\t")
      match parts
        Cons(stateArg, Cons(lastArg, Cons(lenStr, _rest))) ->
          {
            val b64len = lenStr.trim.parse-int.default(-1)
            if b64len < 0 then exn/throw("invalid base64 length")
            val chunks = read-b64(b64len, Nil)
            val b64 = chunks.reverse.join("")
            if b64.count != b64len then exn/throw("base64 length mismatch")
            val input = base64/decode-utf8(b64)
            val last = if lastArg == "-" then Nothing else Just(lastArg)
            val (tokens, _errors) =
              if xmlFixup then
                tokenizer/tokenize-xml(input, state-from-arg(stateArg), last)
              else
                tokenizer/tokenize(input, state-from-arg(stateArg), last)
            val toks = tokens.filter(fn(t) match t { TokEOF -> False; _ -> True })
            val out = json/arr(toks.map(token-json))
            go(i + 1, Cons(out, outs))
          }
        _ -> exn/throw("invalid batch line (expected 3 tab-separated fields)")

  json/arr(go(0, Nil)).println

fun has-prefix(s: string, pre: string) : <div,exn> bool
  val sv = string/vector(s)
  val pv = string/vector(pre)
  if pv.length > sv.length then False else
    {
      var ok := True
      var i := 0
      while(fn(){ ok && i < pv.length }, fn(){
        ok := (sv[i] == pv[i])
        i := i + 1
      })
      ok
    }

fun drop-chars(s: string, n: int) : <div,exn> string
  val cs = string/vector(s)
  var acc : list<char> := Nil
  var i := n
  while(fn(){ i < cs.length }, fn(){
    acc := Cons(cs[i], acc)
    i := i + 1
  })
  string/listchar/string(acc.reverse)

fun parsefragmentcontext(s: string) : <div,exn> fragmentcontext
  if has-prefix(s, "svg ") then
    Fragmentcontext(drop-chars(s, 4), Svg)
  elif has-prefix(s, "math ") then
    Fragmentcontext(drop-chars(s, 5), Math)
  else
    Fragmentcontext(s, Html)

fun tree-case-json(dump: string, errCount: int) : <div,exn> string
  // Output shape: [ "<tree dump>", <error_count> ]
  json/arr([json/escape-string(dump), int/show(errCount)])

fun run-tree-batch() : <console,div,exn> ()
  // stdin protocol:
  // - First line: integer N
  // - Per case:
  //   - Header line: "<kind>\t<contextOr->\t<script(on|off|-)>\t<base64_char_len>"
  //   - Followed by as many base64 chunk lines (<= ~900 chars) as needed
  // Where:
  //   - kind: "doc" | "frag"
  //   - context: for frag, same string as in html5lib .dat (#document-fragment)
  val n = readline().trim.parse-int.default(0)

  fun read-b64(remaining: int, acc: list<string>) : <console,div,exn> list<string>
    if remaining <= 0 then acc else
      val chunk = readline()
      read-b64(remaining - chunk.count, Cons(chunk, acc))

  fun go(i: int, outs: list<string>) : <console,div,exn> list<string>
    if i >= n then outs.reverse else
      val header = readline()
      val parts = string/sep/split(header, "\t")
      match parts
        Cons(kind, Cons(ctxStr, Cons(scriptArg, Cons(lenStr, _rest)))) ->
          {
            val b64len = lenStr.trim.parse-int.default(-1)
            if b64len < 0 then exn/throw("invalid base64 length")
            val chunks = read-b64(b64len, Nil)
            val b64 = chunks.reverse.join("")
            if b64.count != b64len then exn/throw("base64 length mismatch")
            val input = base64/decode-utf8(b64)
            val scripting = (scriptArg != "off")
            val opts = html5/Parseoptions(True, False, scripting, False)
            val res =
              if kind == "frag" then
                html5/parse-fragment(input, parsefragmentcontext(ctxStr), opts)
              else
                html5/parse(input, opts)
            val dump = html5/to-test-format(res.dom)
            val out = tree-case-json(dump, res.errors.length)
            go(i + 1, Cons(out, outs))
          }
        _ -> exn/throw("invalid batch line (expected 4 tab-separated fields)")

  json/arr(go(0, Nil)).println

fun run-encoding-batch() : <console,div,exn> ()
  // stdin protocol:
  // - First line: integer N
  // - Per case:
  //   - Header line: "<transportOr->\t<base64_char_len>"
  //   - Followed by as many base64 chunk lines (<= ~900 chars) as needed
  val n = readline().trim.parse-int.default(0)

  fun read-b64(remaining: int, acc: list<string>) : <console,div,exn> list<string>
    if remaining <= 0 then acc else
      val chunk = readline()
      read-b64(remaining - chunk.count, Cons(chunk, acc))

  fun go(i: int, outs: list<string>) : <console,div,exn> list<string>
    if i >= n then outs.reverse else
      val header = readline()
      val parts = string/sep/split(header, "\t")
      match parts
        Cons(transportArg, Cons(lenStr, _rest)) ->
          {
            val b64len = lenStr.trim.parse-int.default(-1)
            if b64len < 0 then exn/throw("invalid base64 length")
            val chunks = read-b64(b64len, Nil)
            val b64 = chunks.reverse.join("")
            if b64.count != b64len then exn/throw("base64 length mismatch")
            val bytes = base64/decode-bytes(b64)
            val transport = if transportArg == "-" then Nothing else Just(transportArg)
            val enc = encoding/sniff-encoding(bytes, transport)
            go(i + 1, Cons(json/escape-string(enc), outs))
          }
        _ -> exn/throw("invalid batch line (expected 2 tab-separated fields)")

  json/arr(go(0, Nil)).println

fun saw-leading-doctype(ts: list<tokenizer/tokenloc>) : <div,exn> bool
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

  match ts
    Nil -> False
    Cons(Tokenloc(t, _line, _col), rest) ->
      match t
        TokDoctype(_,_,_,_) -> True
        TokComment(_) -> saw-leading-doctype(rest)
        TokCharacter(s) -> if is-ws-only(s) then saw-leading-doctype(rest) else False
        _ -> False

fun run-tree-debug(args: list<string>) : <console,fsys,div,exn> ()
  // args: tree-debug <inputPath> [script(on|off)]
  val pathStr = args.drop(1).head("")
  val scriptArg = args.drop(2).head("on")
  val input = read-text-file(path(pathStr))
  val scripting = (scriptArg != "off")
  val (tokens, tokErrors) = tokenizer/tokenize-for-parse(input, Data, Nothing, scripting)
  val (dom0, treeErrs) = treebuilder/build-document(tokens, scripting)
  val missing = if saw-leading-doctype(tokens) then 0 else 1
  val out =
    json/obj([
      ("tokenizer_errors", int/show(tokErrors.length)),
      ("treebuilder_errors", int/show(treeErrs.length)),
      ("missing_doctype_injected", int/show(missing)),
      ("total_errors", int/show(tokErrors.length + treeErrs.length + missing)),
      ("tree", json/escape-string(html5/to-test-format(dom0))),
    ])
  out.println

pub fun main()
  val args = get-args()
  match args
    Cons(cmd, rest) ->
      match cmd
        "tokenizer" -> run-tokenizer(Cons(cmd, rest))
        "tokenizer-batch" -> run-tokenizer-batch(False)
        "tokenizer-batch-xml" -> run-tokenizer-batch(True)
        "tree-batch" -> run-tree-batch()
        "encoding-batch" -> run-encoding-batch()
        "tree-debug" -> run-tree-debug(Cons(cmd, rest))
        _ -> "usage: cli tokenizer <state> <lastStartTagOr-> <inputPath> | cli tokenizer-batch | cli tree-batch | cli encoding-batch".println
    _ -> "usage: cli tokenizer <state> <lastStartTagOr-> <inputPath> | cli tokenizer-batch | cli tree-batch | cli encoding-batch".println

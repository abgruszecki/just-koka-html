module cli

import std/os/env
import std/os/file
import std/os/path
import std/os/readline
import std/core/string
import std/core/int

import html5/json
import html5/base64
import html5/tokenizer
import html5/dom

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
        val pub-id =
          match publicId
            Nothing -> "null"
            Just(x) -> json/escape-string(x)
        val sys-id =
          match systemId
            Nothing -> "null"
            Just(x) -> json/escape-string(x)
        val quirks = if forceQuirks then "false" else "true"
        json/arr([json/escape-string("DOCTYPE"), json/escape-string(name), pub-id, sys-id, quirks])
      }

fun run-tokenizer(args: list<string>) : <console,fsys,div,exn> ()
  // args: tokenizer <state> <lastStartTagOr-> <inputPath>
  val stateArg = args.drop(1).head("Data")
  val _last = args.drop(2).head("-")
  val pathStr = args.drop(3).head("")
  val input = read-text-file(path(pathStr))
  val (tokens, _errors) = tokenizer/tokenize(input, state-from-arg(stateArg))
  // Drop EOF for html5lib comparison (EOF isn't in expected outputs).
  val toks = tokens.filter(fn(t) match t { TokEOF -> False; _ -> True })
  val out = json/arr(toks.map(token-json))
  out.println

fun run-tokenizer-batch() : <console,div,exn> ()
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
        Cons(stateArg, Cons(_last, Cons(lenStr, _rest))) ->
          {
            val b64len = lenStr.trim.parse-int.default(-1)
            if b64len < 0 then exn/throw("invalid base64 length")
            val chunks = read-b64(b64len, Nil)
            val b64 = chunks.reverse.join("")
            if b64.count != b64len then exn/throw("base64 length mismatch")
            val input = base64/decode-utf8(b64)
            val (tokens, _errors) = tokenizer/tokenize(input, state-from-arg(stateArg))
            val toks = tokens.filter(fn(t) match t { TokEOF -> False; _ -> True })
            val out = json/arr(toks.map(token-json))
            go(i + 1, Cons(out, outs))
          }
        _ -> exn/throw("invalid batch line (expected 3 tab-separated fields)")

  json/arr(go(0, Nil)).println

pub fun main()
  val args = get-args()
  match args
    Cons(cmd, rest) ->
      match cmd
        "tokenizer" -> run-tokenizer(Cons(cmd, rest))
        "tokenizer-batch" -> run-tokenizer-batch()
        _ -> "usage: cli tokenizer <state> <lastStartTagOr-> <inputPath> | cli tokenizer-batch".println
    _ -> "usage: cli tokenizer <state> <lastStartTagOr-> <inputPath> | cli tokenizer-batch".println

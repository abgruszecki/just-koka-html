module cli

import std/os/env
import std/os/file
import std/os/path

import html5/json
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

pub fun main()
  val args = get-args()
  match args
    Cons(cmd, rest) ->
      match cmd
        "tokenizer" -> run-tokenizer(Cons(cmd, rest))
        _ -> "usage: cli tokenizer <state> <lastStartTagOr-> <inputPath>".println
    _ -> "usage: cli tokenizer <state> <lastStartTagOr-> <inputPath>".println

module html5/json

import std/core/string
import std/core/show

// Minimal JSON string escaping (enough for test output and stable interop with Python).
pub fun escape-string(s: string) : <div,exn> string
  val cs = string/vector(s)
  var parts : list<string> := Nil
  parts := Cons("\"", parts)
  var i := 0
  while(fn(){
    i < cs.length
  }, fn(){
    val c = cs[i]
    val piece =
      if c == '\"' then "\\\""
      elif c == '\\' then "\\\\"
      elif c == '\n' then "\\n"
      elif c == '\r' then "\\r"
      elif c == '\t' then "\\t"
      elif c.int < 0x20 then
        "\\u" ++ show/show-hex(c.int, 4, False, "")
      else
        char/string(c)
    parts := Cons(piece, parts)
    i := i + 1
  })
  parts := Cons("\"", parts)
  parts.reverse.join("")

pub fun obj(pairs: list<(string,string)>) : <div> string
  // pairs are (keyJson, valJson) where both are already JSON fragments.
  "{" ++ pairs.map(fn((k,v)) k ++ ":" ++ v).join(",") ++ "}"

pub fun arr(items: list<string>) : string
  "[" ++ items.join(",") ++ "]"

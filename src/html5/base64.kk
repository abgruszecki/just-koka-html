module html5/base64

import std/core/char
import std/core/exn
import std/core/string
import std/core/vector
import std/core/int
import std/num/int32

// Decode a base64-encoded UTF-8 payload into a Koka string.
// This is tailored for the test runner transport layer (stdin framing).
pub fun decode-utf8(b64: string) : <div,exn> string
  val bytes = decode-bytes(b64)
  utf8-bytes-to-string(bytes)

pub fun decode-bytes(b64: string) : <div,exn> vector<int>
  val cs = string/vector(b64)
  var out : list<int> := Nil
  // current 24-bit buffer and number of 6-bit groups collected
  var buf : int32 := 0.int32
  var groups := 0

  var i := 0
  while(fn(){ i < cs.length }, fn(){
    val c = cs[i]
    i := i + 1
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' then
      ()
    elif c == '=' then
      // padding: stop processing further input
      i := cs.length
    else
      val v = base64-val(c)
      buf := buf.shl(6).or(v.int32)
      groups := groups + 1
      if groups == 4 then
        out := Cons(buf.shr(16).and(0xFF.int32).int, out)
        out := Cons(buf.shr(8).and(0xFF.int32).int, out)
        out := Cons(buf.and(0xFF.int32).int, out)
        buf := 0.int32
        groups := 0
  })

  // Handle leftover groups without explicit '=' padding.
  if groups == 2 then
    // 12 bits => 1 byte: xxxxxxxx xxxx
    out := Cons(buf.shr(4).and(0xFF.int32).int, out)
  elif groups == 3 then
    // 18 bits => 2 bytes: xxxxxxxx xxxxxxxx xx
    out := Cons(buf.shr(10).and(0xFF.int32).int, out)
    out := Cons(buf.shr(2).and(0xFF.int32).int, out)
  elif groups == 0 then
    ()
  else
    // groups == 1 is invalid base64
    exn/throw("invalid base64 length")

  vector/list/vector(out.reverse)

fun base64-val(c: char) : <div,exn> int
  if c >= 'A' && c <= 'Z' then c.int - 'A'.int
  elif c >= 'a' && c <= 'z' then 26 + (c.int - 'a'.int)
  elif c >= '0' && c <= '9' then 52 + (c.int - '0'.int)
  elif c == '+' then 62
  elif c == '/' then 63
  else exn/throw("invalid base64 character: " ++ char/string(c))

fun utf8-bytes-to-string(bytes: vector<int>) : <div,exn> string
  var chars : list<char> := Nil
  var i := 0
  while(fn(){ i < bytes.length }, fn(){
    val b0 = bytes[i]
    if b0 < 0 || b0 > 255 then
      exn/throw("invalid byte value")
    val b0i = b0.int32
    if b0 < 0x80 then
      chars := Cons(b0.char, chars)
      i := i + 1
    elif b0i.and(0xE0.int32) == 0xC0.int32 then
      if i + 1 >= bytes.length then exn/throw("truncated utf8")
      val b1 = bytes[i + 1]
      val b1i = b1.int32
      if b1i.and(0xC0.int32) != 0x80.int32 then exn/throw("invalid utf8 continuation")
      val cp = b0i.and(0x1F.int32).int * 64 + b1i.and(0x3F.int32).int
      chars := Cons(cp.char, chars)
      i := i + 2
    elif b0i.and(0xF0.int32) == 0xE0.int32 then
      if i + 2 >= bytes.length then exn/throw("truncated utf8")
      val b1 = bytes[i + 1]
      val b2 = bytes[i + 2]
      val b1i = b1.int32
      val b2i = b2.int32
      if b1i.and(0xC0.int32) != 0x80.int32 || b2i.and(0xC0.int32) != 0x80.int32 then
        exn/throw("invalid utf8 continuation")
      val cp =
        b0i.and(0x0F.int32).int * 4096 +
        b1i.and(0x3F.int32).int * 64 +
        b2i.and(0x3F.int32).int
      chars := Cons(cp.char, chars)
      i := i + 3
    elif b0i.and(0xF8.int32) == 0xF0.int32 then
      if i + 3 >= bytes.length then exn/throw("truncated utf8")
      val b1 = bytes[i + 1]
      val b2 = bytes[i + 2]
      val b3 = bytes[i + 3]
      val b1i = b1.int32
      val b2i = b2.int32
      val b3i = b3.int32
      if b1i.and(0xC0.int32) != 0x80.int32 || b2i.and(0xC0.int32) != 0x80.int32 || b3i.and(0xC0.int32) != 0x80.int32 then
        exn/throw("invalid utf8 continuation")
      val cp =
        b0i.and(0x07.int32).int * 262144 +
        b1i.and(0x3F.int32).int * 4096 +
        b2i.and(0x3F.int32).int * 64 +
        b3i.and(0x3F.int32).int
      chars := Cons(cp.char, chars)
      i := i + 4
    else
      exn/throw("invalid utf8 lead byte")
  })
  string/listchar/string(chars.reverse)

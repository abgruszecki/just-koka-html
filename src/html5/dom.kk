module html5/dom

import std/core/vector

pub type namespace {
  Html
  Svg
  Math
}

pub type attrnamespace {
  None
  XLink
  Xml
  Xmlns
}

pub struct qname(ns: namespace, local: string)
pub struct attrname(ns: attrnamespace, local: string)
pub struct attr(name: attrname, value: string)

pub alias nodeid = int

pub type node {
  Document(children: list<nodeid>, quirks-mode: string)
  Element(name: string, ns: namespace, attrs: list<attr>, children: list<nodeid>)
  Text(data: string)
}

pub struct dom(nodes: vector<node>, root: nodeid)

pub fun node(dom: dom, id: nodeid) : <exn> node
  dom.nodes[id]

pub fun children(dom: dom, id: nodeid) : <exn> list<nodeid>
  match node(dom,id)
    Document(children,_) -> children
    Element(_,_,_,children) -> children
    Text(_) -> Nil

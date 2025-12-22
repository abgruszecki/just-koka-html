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

pub struct fragmentcontext(tag: string, ns: namespace)

pub struct doctype(
  name: string,
  public-id: maybe<string>,
  system-id: maybe<string>,
  force-quirks: bool
)

pub type node {
  Document(children: list<nodeid>, quirks-mode: string)
  DocumentFragment(children: list<nodeid>, frag-ctx: maybe<fragmentcontext>)
  Element(name: string, ns: namespace, attrs: list<attr>, children: list<nodeid>)
  Template(ns: namespace, attrs: list<attr>, children: list<nodeid>, content: nodeid)
  Text(data: string)
  Comment(data: string)
  DoctypeNode(doctype: doctype)
}

pub struct dom(nodes: vector<node>, root: nodeid)

pub fun node(dom: dom, id: nodeid) : <exn> node
  dom.nodes[id]

pub fun children(dom: dom, id: nodeid) : <exn> list<nodeid>
  match node(dom,id)
    Document(children,_) -> children
    DocumentFragment(children,_) -> children
    Element(_,_,_,children) -> children
    Template(_,_,children,_) -> children
    Text(_) -> Nil
    Comment(_) -> Nil
    DoctypeNode(_) -> Nil

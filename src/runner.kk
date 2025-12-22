module runner

import html5
import html5/serialize

pub fun main()
  val html = "<html><head></head><body><p>Hello</p></body></html>"
  val result = html5/parse(html)
  html5/to-test-format(result.dom).print

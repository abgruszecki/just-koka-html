module html5/errors

pub struct parseerror(code: string, line: int, col: int)

pub fun parseerror-at(code: string, line: int, col: int) : parseerror
  Parseerror(code, line, col)

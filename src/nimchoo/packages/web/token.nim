## The server's secret: 128 random bits as 32 hex digits, kept in a file in the cache
## directory that only the user can read.  The URL that a command with a page opens carries it once;
## the browser then keeps it in a cookie (see handler.nim), so bookmarks keep working
## across runs.  `renew` makes a new one (the old cookies stop working).

import std/[options, os, sequtils, strutils]

{.push raises: [].}

const tokenFileName* = "server-token"

func isToken*(s: string): bool =
  ## 32 lower-case hex digits.
  s.len == 32 and s.allIt(it in {'0' .. '9', 'a' .. 'f'})

type TokenResult* = object ## The token, or what went wrong (not both).
  case ok*: bool
  of true:
    token*: string
  of false:
    problem*: string

proc randomToken(): Option[string] =
  ## 16 bytes from the system's random source; none if that cannot be read.
  var bytes: array[16, byte]
  try:
    let f = open("/dev/urandom", fmRead)
    defer:
      f.close()
    if f.readBytes(bytes, 0, 16) != 16:
      return none(string)
  except IOError:
    return none(string)
  var text = ""
  for b in bytes:
    text.add toLowerAscii(toHex(int(b), 2))
  some(text)

proc loadToken*(dir: string, renew = false): TokenResult =
  ## The token in `dir`, made (with the directory) if there is none, or if it is not a
  ## token, or if `renew`.  The file can be read only by its owner from the moment it
  ## exists.  The result says what went wrong, if something did.
  let path = dir / tokenFileName
  try:
    if not renew and fileExists(path):
      let old = readFile(path).strip
      if isToken(old):
        return TokenResult(ok: true, token: old)
    createDir dir
    let made = randomToken()
    if made.isNone:
      return
        TokenResult(ok: false, problem: "cannot read random numbers from /dev/urandom")
    let t = made.get
    let f = open(path, fmWrite) # (created empty, locked down, then filled)
    try:
      setFilePermissions(path, {fpUserRead, fpUserWrite})
      f.write t & "\n"
    finally:
      f.close()
    TokenResult(ok: true, token: t)
  except IOError, OSError:
    TokenResult(
      ok: false,
      problem:
        "cannot keep the server's token in " & path & ": " & getCurrentExceptionMsg(),
    )

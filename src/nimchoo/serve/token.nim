## The server's secret: 128 random bits as 32 hex digits, kept in a file in the cache
## directory that only the user can read.  The URL that `--web` opens carries it once;
## the browser then keeps it in a cookie (see handler.nim), so bookmarks keep working
## across runs.  `renew` makes a new one (the old cookies stop working).

import std/[os, sequtils, strutils]

{.push raises: [].}

const tokenFileName* = "server-token"

func isToken*(s: string): bool =
  ## 32 lower-case hex digits.
  s.len == 32 and s.allIt(it in {'0' .. '9', 'a' .. 'f'})

proc randomToken(): string =
  ## 16 bytes from the system's random source; "" if that cannot be read.
  var bytes: array[16, byte]
  try:
    let f = open("/dev/urandom", fmRead)
    defer: f.close()
    if f.readBytes(bytes, 0, 16) != 16: return ""
  except IOError:
    return ""
  for b in bytes: result.add toLowerAscii(toHex(int(b), 2))

proc loadToken*(dir: string, renew = false): tuple[token, problem: string] =
  ## The token in `dir`, made (with the directory) if there is none, or if it is not a
  ## token, or if `renew`.  The file can be read only by its owner from the moment it
  ## exists.  `problem` says what went wrong ("" if nothing did).
  let path = dir / tokenFileName
  try:
    if not renew and fileExists(path):
      let old = readFile(path).strip
      if isToken(old): return (old, "")
    createDir dir
    let t = randomToken()
    if t.len == 0: return ("", "cannot read random numbers from /dev/urandom")
    let f = open(path, fmWrite)          # (created empty, locked down, then filled)
    try:
      setFilePermissions(path, {fpUserRead, fpUserWrite})
      f.write t & "\n"
    finally:
      f.close()
    (t, "")
  except IOError, OSError:
    ("", "cannot keep the server's token in " & path & ": " & getCurrentExceptionMsg())

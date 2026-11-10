## The checks that decide what the local web server will do with a request.  Pure: no
## sockets, no files, no processes, so every rule is tested directly.
##
## The server runs `nch` commands named in URLs, and any web page open in the browser
## can send requests to localhost, so the rules are strict: the Host header must be
## ours (against DNS rebinding), the token must be right, only the commands in
## `commandRules` may be run, with only their options, and the values must be of the
## kind a cache file name can hold.

import std/[options, sequtils, strutils, uri]
import ../cache/cache
import ../selection/bits

{.push raises: [].}

type
  Query* = seq[(string, string)]

  Target* = object
    path*: string
    query*: Query

  Route* = object
    case isFile*: bool
    of true:
      fileName*: string ## in the cache directory
    of false:
      command*: string
      args*: seq[string] ## for `nch COMMAND --worker ARGS`
      pin*: string ## the option that fixes what the page shows ("": none)

  CommandRule* = object
    name*: string
    options*: seq[string] ## `?name=value` becomes `--name value`
    flags*: seq[string] ## `?name=1` becomes `--name`
    pin*: string
      ## the key of the data: if a request lacks it, the address is
      ## sent on with the key the worker used (so that a reload
      ## shows the same data)

const
  maxTarget = 8000
  cookieName* = "nch"
  cookieMaxAge* = 365 * 24 * 3600
    ## seconds: a bookmark works for a year, not only until the browser is closed
  tokenParam* = "token"
  defaultPort* = 62466 ## the digits of "mchoo" on a phone keypad
  # the commands the server may run: read-only, safe to repeat; with their options
  commandRules* = [
    CommandRule(name: "map", options: @["bits", "check"], pin: "bits"),
    CommandRule(
      name: "ff",
      options: @["check", "model", "from", "to", "fitness-scale", "fatigue-scale"],
      flags: @["hourly", "utc"],
      pin: "check",
    ),
  ]

func parseTarget*(raw: string): Option[Target] =
  ## "/map?bits=AsBO&check=ab12cd" -> path "/map" and the query, percent-decoded.
  ## None for anything that is not a plain path (no scheme or host, as written or as decoded,
  ## no spaces or control characters, not too long).
  if raw.len == 0 or raw.len > maxTarget or raw[0] != '/' or raw.startsWith("//"):
    return none(Target)
  if raw.anyIt(it <= ' ' or it == '\x7f' or it == '\\'):
    return none(Target)
  let q = raw.find('?')
  var t = Target(
    path: decodeUrl(
      if q < 0:
        raw
      else:
        raw[0 ..< q],
      decodePlus = false,
    )
  )
  if t.path.startsWith("//"):
    return
      none(Target) # (decoded from "/%2f...": as a redirect it would name another host)
  if q >= 0:
    for pair in raw[q + 1 .. ^1].split('&'):
      if pair.len == 0:
        continue
      let eq = pair.find('=')
      if eq < 0:
        t.query.add (decodeUrl(pair, decodePlus = false), "")
      else:
        t.query.add (
          decodeUrl(pair[0 ..< eq], decodePlus = false),
          decodeUrl(pair[eq + 1 .. ^1], decodePlus = false),
        )
  some(t)

func queryValue*(q: Query, name: string): Option[string] =
  ## The value of the first parameter with the name, if any.
  for (k, v) in q:
    if k == name:
      return some(v)
  none(string)

func encodedPath(path: string): string =
  ## A decoded path written as an address again: each segment encoded (so that a `%`, `?`, `#`, space or control
  ## character in it is not read as something else, or as the end of the line in the log and the headers).
  path.split('/').mapIt(encodeUrl(it, usePlus = false)).join("/")

func withoutParam*(t: Target, name: string): string =
  ## The target as a path and query again, without the parameter `name`; it reads back as the same path and query.
  result = encodedPath(t.path)
  var first = true
  for (k, v) in t.query:
    if k == name:
      continue
    result.add (if first: "?" else: "&")
    first = false
    result.add encodeUrl(k, usePlus = false) & "=" & encodeUrl(v, usePlus = false)

func hostAllowed*(host: string, port: int): bool =
  ## The Host header must be this server's own address: "127.0.0.1:PORT" or
  ## "localhost:PORT" (so a name that points at 127.0.0.1 from elsewhere does not do).
  let h = host.toLowerAscii
  h == "127.0.0.1:" & $port or h == "localhost:" & $port

func cookieValue*(header, name: string): string =
  ## The value of the cookie `name` in a Cookie header ("" if there is none).
  for part in header.split(';'):
    let p = part.strip
    if p.startsWith(name & "="):
      return p[name.len + 1 .. ^1]

func sameToken*(a, b: string): bool =
  ## Whether the two are equal, without stopping at the first difference (so the time
  ## it takes does not tell how much was right).
  if a.len != b.len or a.len == 0:
    return false
  var diff = 0
  for i in 0 ..< a.len:
    diff = diff or (ord(a[i]) xor ord(b[i]))
  diff == 0

func isPlainNumber(value: string): bool =
  ## digits and at most one dot, not starting or ending with it
  value.len in 1 .. 8 and value.allIt(it in {'0' .. '9', '.'}) and value.count('.') <= 1 and
    value[0] != '.' and value[^1] != '.'

func isDay(value: string): bool =
  value.len == 10 and value[4] == '-' and value[7] == '-' and
    value.allIt(it in {'0' .. '9', '-'})

func validValue(command, option, value: string): bool =
  ## What an option of a command may be set to.
  if option == "bits":
    return
      value.len > 0 and isBitsString(value)
        # (a list of activities may have two dashes in a row)
  if not isOptionValue(value):
    return false
  case option
  of "check":
    value.allIt(it in {'0' .. '9', 'a' .. 'f'})
  # (a hash)
  of "fitness-scale", "fatigue-scale":
    isPlainNumber(value)
  # (a multiplier)
  of "from", "to":
    isDay(value)
  else:
    true

func route*(t: Target): Option[Route] =
  ## What a request is for: a file of the cache directory (`/files/NAME`), or a command
  ## (`/COMMAND?option=value...`) that is on the list, with only its options, each once.
  let segments = t.path.split('/') # "/a/b" -> ["", "a", "b"]
  if segments.len == 3 and segments[0] == "" and segments[1] == "files":
    if t.query.len == 0 and isCacheFileName(segments[2]):
      return some(Route(isFile: true, fileName: segments[2]))
    return none(Route)
  if segments.len != 2 or segments[0] != "":
    return none(Route)
  for rule in commandRules:
    if segments[1] != rule.name:
      continue
    var args: seq[string]
    var seen: seq[string]
    for (k, v) in t.query:
      if k == tokenParam:
        continue
      if k in seen:
        return none(Route)
      seen.add k
      if k in rule.flags:
        if v != "1":
          return none(Route)
        args.add "--" & k
      elif k in rule.options and validValue(rule.name, k, v):
        args.add "--" & k
        args.add v
      else:
        return none(Route)
    return some(Route(isFile: false, command: rule.name, args: args, pin: rule.pin))
  none(Route)

## The checks that decide what the local web server will do with a request.  Pure: no
## sockets, no files, no processes, so every rule is tested directly.
##
## The server runs `nch` commands named in URLs, and any web page open in the browser
## can send requests to localhost, so the rules are strict: the Host header must be
## ours (against DNS rebinding), the token must be right, only the commands that
## packages have offered as pages (`webPage`) may be run, with only their options, and the
## values must be of the kind a cache file name can hold.

import std/[options, sequtils, strutils, uri]
import ../../core/extension
import ../cache/cache
import ../util/args/args

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

  PageOption* = object
    name*: string ## `?name=value` becomes `--name value`
    valid*: Validator

  WebPage* = object
    ## A command the server may run for a page, as a package offers it (the point `webPage`): the command
    ## and the options it may be given.
    command*: string
    options*: seq[PageOption]
    flags*: seq[string] ## `?name=1` becomes `--name`
    pin*: string
      ## the key of the data: if a request lacks it, the address is
      ## sent on with the key the worker used (so that a reload
      ## shows the same data)

func pageOf*[P](command: string, spec: Spec[P], pin: string): WebPage =
  ## The page a command offers the server, made from its own options: those marked as allowed in an address, each with
  ## its check, and the flags.  What the server will pass on is then what the command parses, and nothing else.
  result = WebPage(command: command, pin: pin)
  for o in spec.opts:
    if o.address == adNo:
      continue
    let long = o.names.filterIt(it.startsWith("--"))
    doAssert long.len > 0
    let name = long[0][2 .. ^1]
    case o.address
    of adFlag:
      result.flags.add name
    of adValue:
      doAssert o.valid != nil,
        "an option allowed in an address needs a check for its value: " & name
      result.options.add PageOption(name: name, valid: o.valid)
    of adNo:
      discard

const webPage* = ExtensionPoint[WebPage](name: "web/pages")
  ## The pages the server may run, offered by the packages that have them (`map`, `ff`).

const
  maxTarget = 8000
  cookieName* = "nch"
  cookieMaxAge* = 365 * 24 * 3600
    ## seconds: a bookmark works for a year, not only until the browser is closed
  tokenParam* = "token"
  defaultPort* = 62466 ## the digits of "mchoo" on a phone keypad

func encodedPath(path: string): string =
  ## A decoded path written as an address again: each segment encoded (so that a `%`, `?`, `#`, space or control
  ## character in it is not read as something else, or as the end of the line in the log and the headers).
  path.split('/').mapIt(encodeUrl(it, usePlus = false)).join("/")

func render(t: Target, skip: string, skipping: bool): string =
  ## The target as a path and query again, canonically encoded, without the parameter `skip` if `skipping`.
  result = encodedPath(t.path)
  var first = true
  for (k, v) in t.query:
    if skipping and k == skip:
      continue
    result.add (if first: "?" else: "&")
    first = false
    result.add encodeUrl(k, usePlus = false) & "=" & encodeUrl(v, usePlus = false)

func withoutParam*(t: Target, name: string): string =
  ## The target as a path and query again, without the parameter `name`; it reads back as the same path and query.
  render(t, name, true)

func parseTarget*(raw: string): Option[Target] =
  ## "/map?bits=AsBO&check=ab12cd" -> path "/map" and the query, percent-decoded.
  ## None for anything that is not a plain path (no scheme or host, as written or as decoded,
  ## no spaces or control characters, not too long as written or as written back).
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
  if render(t, "", false).len > maxTarget:
    return none(Target)
      # (the address as it is written back is longer than the raw one: each byte may be %XX)
  some(t)

func queryValue*(q: Query, name: string): Option[string] =
  ## The value of the first parameter with the name, if any.
  for (k, v) in q:
    if k == name:
      return some(v)
  none(string)

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

func anyWord*(value: string): bool =
  ## Anything a cache file name can hold (see `isOptionValue`).
  isOptionValue(value)

func hexHash*(value: string): bool =
  ## A hash: hex digits.
  isOptionValue(value) and value.allIt(it in {'0' .. '9', 'a' .. 'f'})

func plainNumber*(value: string): bool =
  ## Digits and at most one dot, not starting or ending with it, up to 8 characters.
  isOptionValue(value) and value.len in 1 .. 8 and value.allIt(it in {'0' .. '9', '.'}) and
    value.count('.') <= 1 and value[0] != '.' and value[^1] != '.'

func day*(value: string): bool =
  ## A day, "2018-08-31".
  isOptionValue(value) and value.len == 10 and value[4] == '-' and value[7] == '-' and
    value.allIt(it in {'0' .. '9', '-'})

func route*(t: Target, pages: seq[WebPage]): Option[Route] =
  ## What a request is for: a file of the cache directory (`/files/NAME`), or a command
  ## (`/COMMAND?option=value...`) that a page offers, with only its options, each once.
  let segments = t.path.split('/') # "/a/b" -> ["", "a", "b"]
  if segments.len == 3 and segments[0] == "" and segments[1] == "files":
    if t.query.len == 0 and isCacheFileName(segments[2]):
      return some(Route(isFile: true, fileName: segments[2]))
    return none(Route)
  if segments.len != 2 or segments[0] != "":
    return none(Route)
  for page in pages:
    if segments[1] != page.command:
      continue
    var args: seq[string]
    var seen: seq[string]
    for (k, v) in t.query:
      if k == tokenParam:
        continue
      if k in seen:
        return none(Route)
      seen.add k
      if k in page.flags:
        if v != "1":
          return none(Route)
        args.add "--" & k
      else:
        let option = page.options.filterIt(it.name == k)
        if option.len == 0 or not option[0].valid(v):
          return none(Route)
        args.add "--" & k
        args.add v
    return some(Route(isFile: false, command: page.command, args: args, pin: page.pin))
  none(Route)

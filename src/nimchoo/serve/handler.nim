## What the local web server answers.  Everything it decides is here, as a function from
## a request to a reply, with the running of the worker (`nch COMMAND --worker`) passed in
## so that tests need neither a socket nor a subprocess.  (The socket loop is server.nim.)
##
## A request must (1) be a GET, (2) have our own address in its Host header, (3) carry the
## token, in the cookie, or once in the URL (then the cookie is set and the browser is sent
## on to the same address without it).  Then it is a page (`/heatmap?check=...`: the worker
## makes the files and the first it names is sent) or a file of the cache directory
## (`/files/NAME`).  Anything else is "not found".

import std/[options, os, sequtils, strutils]
import ../cache
import ../ui/logfile
import ./[pages, request]

{.push raises: [].}

type
  WorkerResult* = object
    stdout*, stderr*: string
    code*: int

  WorkerRunner* = proc(args: seq[string]): WorkerResult {.closure, raises: [].}

  ServerConfig* = object
    token*: string
    cacheDir*: string
    run*: WorkerRunner
    baseArgs*: seq[string]          ## the options before the command (--db ..., --user ...)
    log*: Log
    logCommand*: string

  Incoming* = object
    meth*, target*, host*, cookie*: string

  Reply* = object
    code*: int
    headers*: seq[(string, string)]
    body*: string

const
  policy = "default-src 'none'; script-src 'self' 'unsafe-inline' https://unpkg.com; " &
    "style-src 'self' 'unsafe-inline' https://unpkg.com; " &
    "img-src 'self' data: https://tile.openstreetmap.org https://unpkg.com; " &
    "connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
  htmlType = "text/html; charset=utf-8"
  textType = "text/plain; charset=utf-8"

func withSecurity(r: Reply): Reply =
  ## Headers for every reply: what the page may load, and no guessing of content types.
  result = r
  result.headers.add ("Content-Security-Policy", policy)
  result.headers.add ("X-Content-Type-Options", "nosniff")
  result.headers.add ("Cache-Control", "no-cache")

func reply(code: int, body: string, contentType = textType): Reply =
  Reply(code: code, headers: @[("Content-Type", contentType)], body: body)

func contentTypeOf(fileName: string): string =
  if fileName.endsWith(".geojson"): "application/geo+json"
  elif fileName.endsWith(".html"): htmlType
  elif fileName.endsWith(".csv"): "text/csv; charset=utf-8"
  else: "application/octet-stream"

proc readCacheFile(cfg: ServerConfig, name: string): Option[string] =
  ## A file of the cache directory, by a name that has been checked.
  if not isCacheFileName(name): return none(string)
  try:
    some(readFile(cfg.cacheDir / name))
  except IOError:
    none(string)

proc page(cfg: ServerConfig, route: Route, t: Target): Reply =
  ## Run the worker for a command and send the page it makes.
  let r = cfg.run(cfg.baseArgs & @[route.command, "--worker"] & route.args)
  if r.code != 0:
    let why = r.stderr.strip
    return reply(500, "<!DOCTYPE html><meta charset=\"utf-8\"><title>nch</title><pre>" &
      htmlEscape(if why.len > 0: why else: "nch " & route.command & " failed") & "</pre>",
      htmlType)
  let lines = r.stdout.splitLines.filterIt(it.len > 0)
  if lines.len == 0:
    return reply(500, "nch " & route.command & " made no page")
  let name = extractFilename(lines[0])
  if parentDir(lines[0]) != cfg.cacheDir or not name.endsWith(".html"):
    return reply(500, "nch " & route.command & " named a page that is not in the cache")
  if route.pin.len > 0 and t.query.queryValue(route.pin).isNone:
    # the data were "the current ones": pin their key in the address, so that a reload shows
    # the same data (the other options of the request stay as they were)
    let stem = parseStem(name[0 ..< name.len - ".html".len])
    let key = if stem.isSome: stem.get[1].queryValue(route.pin) else: none(string)
    if key.isSome:
      var q = @[route.pin & "=" & key.get]
      for (k, v) in t.query:
        if k != tokenParam: q.add k & "=" & v
      return Reply(code: 302, headers: @[("Location", "/" & route.command & "?" & q.join("&"))])
  let body = readCacheFile(cfg, name)
  if body.isNone: return reply(404, "not found")
  reply(200, body.get, htmlType)

proc answer(cfg: ServerConfig, port: int, req: Incoming): Reply =
  if req.meth != "GET": return reply(405, "method not allowed")
  if not hostAllowed(req.host, port): return reply(403, "forbidden")
  let target = parseTarget(req.target)
  if target.isNone: return reply(400, "bad request")
  let t = target.get
  let given = t.query.queryValue(tokenParam)
  if given.isSome:
    # the address that `nch ... --web` opens: set the cookie, and go on without the token
    if not sameToken(given.get, cfg.token): return reply(403, "forbidden")
    return Reply(code: 302, headers: @[
      ("Set-Cookie", cookieName & "=" & cfg.token & "; HttpOnly; SameSite=Strict; Path=/"),
      ("Location", t.withoutParam(tokenParam))])
  if not sameToken(cookieValue(req.cookie, cookieName), cfg.token):
    return reply(403, "forbidden: open the address that `nch " & cfg.logCommand &
                   " --web` printed\n")
  let route = route(t)
  if route.isNone: return reply(404, "not found")
  if route.get.isFile:
    let body = readCacheFile(cfg, route.get.fileName)
    if body.isNone: return reply(404, "not found")
    return reply(200, body.get, contentTypeOf(route.get.fileName))
  page(cfg, route.get, t)

proc handle*(cfg: ServerConfig, port: int, req: Incoming): Reply =
  ## The reply to a request (and a line in the log; never the token).
  result = withSecurity(answer(cfg, port, req))
  let shown = block:
    let t = parseTarget(req.target)
    if t.isSome: t.get.withoutParam(tokenParam) else: "(unreadable)"
  let line = req.meth & " " & shown & " " & $result.code
  if result.code == 403 or result.code == 400 or result.code == 405:
    cfg.log.log(lvWarn, cfg.logCommand, leDenied, line)
  else:
    cfg.log.log(lvInfo, cfg.logCommand, leServed, line)

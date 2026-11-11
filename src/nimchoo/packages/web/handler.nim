## What the local web server answers.  Everything it decides is here, as functions from a
## request to a reply, in two steps round the one slow thing, the running of the worker
## (`nch COMMAND --worker`): `begin` decides (and for a page says which worker to run),
## `finish` makes the reply from what the worker said.  The server (server.nim) runs the
## worker in between without stopping the other requests; `handle` runs the two steps one
## after the other with a runner it is given, so that tests need neither a socket nor a
## subprocess.
##
## A request must (1) be a GET, (2) have our own address in its Host header, (3) carry the
## token, in the cookie, or once in the URL (then the cookie is set and the browser is sent
## on to the same address without it).  Then it is a page (`/map?selection=...`: the worker
## makes the files and the first it names is sent) or a file of the cache directory
## (`/files/NAME`).  Anything else is "not found".

import std/[options, os, sequtils, strutils]
import ../cache/cache
import ../../core/logfile
import ./[pages, request]

{.push raises: [].}

type
  WorkerResult* = object
    stdout*, stderr*: string
    code*: int

  WorkerRunner* = proc(args: seq[string]): WorkerResult {.closure, raises: [].}
    ## (a blocking one: for tests and `handle`; the server's is asynchronous)

  ServerConfig* = object
    token*: string
    cacheDir*: string
    pages*: seq[WebPage]
      ## the commands it may run for a page (the packages offer them: `webPage`)
    baseArgs*: seq[string] ## the options before the command (--db ..., --user ...)
    log*: Log
    logCommand*: string

  Incoming* = object
    meth*, target*, host*, cookie*: string

  Step* = object
    ## What `begin` made of a request: the reply, or a page that needs a worker run first.
    case needsWorker*: bool
    of false:
      reply*: Reply
    of true:
      args*: seq[string]
        ## the arguments of the worker (the same arguments give the same page)
      route: Route
      target: Target

  Reply* = object
    code*: int
    headers*: seq[(string, string)]
    body*: string

const
  policy =
    "default-src 'none'; script-src 'self' 'unsafe-inline' https://unpkg.com; " &
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
  if fileName.endsWith(".geojson"):
    "application/geo+json"
  elif fileName.endsWith(".html"):
    htmlType
  elif fileName.endsWith(".csv"):
    "text/csv; charset=utf-8"
  else:
    "application/octet-stream"

proc readCacheFile(cfg: ServerConfig, name: string): Option[string] =
  ## A file of the cache directory, by a name that has been checked.
  if not isCacheFileName(name):
    return none(string)
  try:
    some(readFile(cfg.cacheDir / name))
  except IOError:
    none(string)

converter toStep(r: Reply): Step =
  ## (so that a reply that needs nothing more can be returned as it is)
  Step(needsWorker: false, reply: r)

proc page(cfg: ServerConfig, route: Route, t: Target, r: WorkerResult): Reply =
  ## The page that the worker made.
  if r.code != 0:
    let why = r.stderr.strip
    return reply(
      500,
      "<!DOCTYPE html><meta charset=\"utf-8\"><title>nch</title><pre>" &
        htmlEscape(
          if why.len > 0:
            why
          else:
            "nch " & route.command & " failed"
        ) & "</pre>",
      htmlType,
    )
  let lines = r.stdout.splitLines.filterIt(it.len > 0)
  if lines.len == 0:
    return reply(500, "nch " & route.command & " made no page")
  let name = extractFilename(lines[0])
  if parentDir(lines[0]) != cfg.cacheDir or not name.endsWith(".html"):
    return reply(500, "nch " & route.command & " named a page that is not in the cache")
  if t.query.queryValue(stateParam).isNone and lines.len > 2:
    # the address was for "the current data": the worker's third line is the address that names exactly what it made, and
    # a reload of that shows the same plot
    return
      Reply(code: 302, headers: @[("Location", "/" & route.command & "?" & lines[2])])
  let body = readCacheFile(cfg, name)
  if body.isNone:
    return reply(404, "not found")
  reply(200, body.get, htmlType)

proc answer(cfg: ServerConfig, port: int, req: Incoming): Step =
  if req.meth != "GET":
    return reply(405, "method not allowed")
  if not hostAllowed(req.host, port):
    return reply(403, "forbidden")
  let target = parseTarget(req.target)
  if target.isNone:
    return reply(400, "bad request")
  let t = target.get
  let given = t.query.queryValue(tokenParam)
  if given.isSome:
    # the address that `nch ... --web` opens: set the cookie, and go on without the token
    if not sameToken(given.get, cfg.token):
      return reply(403, "forbidden")
    return Reply(
      code: 302,
      headers: @[
        (
          "Set-Cookie",
          cookieName & "=" & cfg.token & "; HttpOnly; SameSite=Strict; Path=/; Max-Age=" &
            $cookieMaxAge,
        ),
        ("Location", t.withoutParam(tokenParam)),
      ],
    )
  if not sameToken(cookieValue(req.cookie, cookieName), cfg.token):
    return reply(
      403,
      "forbidden: open the address that `nch " & $cfg.logCommand & " --web` printed\n",
    )
  let route = route(t, cfg.pages)
  if route.isNone:
    return reply(404, "not found")
  if route.get.isFile:
    let body = readCacheFile(cfg, route.get.fileName)
    if body.isNone:
      return reply(404, "not found")
    return reply(200, body.get, contentTypeOf(route.get.fileName))
  Step(
    needsWorker: true,
    args: cfg.baseArgs & @[route.get.command, "--worker"] & route.get.args,
    route: route.get,
    target: t,
  )

proc conclude(cfg: ServerConfig, req: Incoming, raw: Reply): Reply =
  ## The reply with the security headers, and a line in the log (never the token).
  result = withSecurity(raw)
  let shown = block:
    let t = parseTarget(req.target)
    if t.isSome:
      t.get.withoutParam(tokenParam)
    else:
      "(unreadable)"
  let line = req.meth & " " & shown & " " & $result.code
  if result.code == 403 or result.code == 400 or result.code == 405:
    cfg.log.log(lvWarn, $cfg.logCommand, leDenied, line)
  else:
    cfg.log.log(lvInfo, $cfg.logCommand, leServed, line)

proc begin*(cfg: ServerConfig, port: int, req: Incoming): Step =
  ## Decide what to do with a request: answer it, or say which worker has to run for it.
  answer(cfg, port, req)

proc answered*(cfg: ServerConfig, req: Incoming, step: Step): Reply =
  ## The reply of a step that did not need a worker.
  doAssert not step.needsWorker,
    "a step that needs a worker is finished with its result"
  conclude(cfg, req, step.reply)

proc finish*(cfg: ServerConfig, req: Incoming, step: Step, r: WorkerResult): Reply =
  ## The reply of a step that needed a worker, given what the worker did.
  doAssert step.needsWorker, "a step that needs no worker has its reply already"
  conclude(cfg, req, page(cfg, step.route, step.target, r))

proc handle*(cfg: ServerConfig, port: int, req: Incoming, run: WorkerRunner): Reply =
  ## The reply to a request, running the worker (if there is one) with `run`.
  let step = begin(cfg, port, req)
  if step.needsWorker:
    finish(cfg, req, step, run(step.args))
  else:
    answered(cfg, req, step)

## `nch COMMAND`: serve a command's pages on localhost (127.0.0.1) and open the browser at one.  From here on the server runs
## `nch COMMAND --worker` for each page request, which makes them from the data as they are then (see handler.nim).  Shared by
## the commands that have pages.
##
## **One server for every page.**  If a server of ours is already answering on the port (its `/status` says so, to the token
## in our header), the command opens its page there and returns, instead of starting another: so the first `nch map` (or
## `nch ff`) stays running, in a terminal of its own or with `&`, and every later one returns at once.  A server from another
## build of nch is warned of (its pages still work: each is made by a worker run from the program as it is now); one for
## another database or user is refused.  `--stop` stops the server, from anywhere (`/stop`).

import std/[net, options, os, osproc, strformat, strutils]
import ../cache/cache
import ../../core/[extension, globals]
import ../db/store
import ../../core/logfile
import ../ui/interrupt
import ../ui/vocabulary
import ../util/version/version
import ./[handler, request, server, token]

{.push raises: [].}

type WebOptions* = object
  port*: int ## the port (0: any free one)
  start*: bool
    ## start the server (if none is running) and print the page's address, without opening the browser
  newToken*: bool ## make a new secret token (the old bookmarks stop working)

proc workerOptions(g: Globals): seq[string] =
  ## The global options the worker needs to look at the same data as this process.
  result = @["--db", resolveDbPath(g.dbPath)]
  if g.user.len > 0:
    result.add @["--user", g.user]

func serverIdentity(args: seq[string]): string =
  ## What a server says it is (`/status`): the build of nch on the first line, the options its workers get on the second.
  versionString & "\n" & args.join(" ")

when declared(SslError):
  # (what the socket raises depends on the build: `SslError` exists, and is raised, when SSL is in it)
  {.
    pragma: socketRaises, raises: [OSError, IOError, TimeoutError, ValueError, SslError]
  .}
else:
  {.pragma: socketRaises, raises: [OSError, IOError, TimeoutError, ValueError].}

proc exchange(
    port: int, token, path: string
): Option[tuple[code: int, body: string]] {.socketRaises.} =
  ## (`ask` without the catching)
  var s = newSocket()
  defer:
    s.close()
  s.connect("127.0.0.1", Port(port), timeout = 1000)
  s.send(
    fmt"GET {path} HTTP/1.1" & "\r\n" & fmt"Host: 127.0.0.1:{port}" & "\r\n" &
      fmt"{tokenHeader}: {token}" & "\r\nConnection: close\r\n\r\n"
  )
  var text = ""
  while true:
    let piece = s.recv(4096, timeout = 2000)
    if piece.len == 0:
      break
    text.add piece
  let head = text.split("\r\n\r\n", maxsplit = 1)
  let status = head[0].splitLines()[0].splitWhitespace()
  if head.len < 2 or status.len < 2 or not status[0].startsWith("HTTP/"):
    return none(tuple[code: int, body: string])
  some((parseInt(status[1]), head[1]))

proc ask(
    port: int, token, path: string
): Option[tuple[code: int, body: string]] {.raises: [].} =
  ## Ask the server on 127.0.0.1:`port` for `path` (`/status`, `/stop`) with the token in our header; none if nothing
  ## answers there as an HTTP server would (no server, or not one that speaks to us).
  when declared(SslError):
    try:
      exchange(port, token, path)
    except OSError, IOError, TimeoutError, ValueError, SslError:
      none(tuple[code: int, body: string])
  else:
    try:
      exchange(port, token, path)
    except OSError, IOError, TimeoutError, ValueError:
      none(tuple[code: int, body: string])

proc openBrowser(url: string): bool =
  ## Ask the desktop to open `url`, without waiting for it and without its chatter.  (The
  ## address is handed to the shell as an argument, not made part of a command line.)
  try:
    discard startProcess(
      "/bin/sh",
      args = @["-c", "xdg-open \"$1\" >/dev/null 2>&1 &", "sh", url],
      options = {poParentStreams},
    )
    true
  except OSError, IOError:
    false

func pageUrl(port: int, path, query, token: string): string =
  ## The address that opens a page (with the token once, which the server turns into a cookie).
  let q =
    if query.len > 0:
      query & "&"
    else:
      ""
  fmt"http://localhost:{port}/{path}?{q}token={token}"

proc showPage(g: Globals, url: string, start: bool) =
  ## Print the page's address and, unless only starting, open the browser at it.
  g.say osOut, url & "\n"
  try:
    stdout.flushFile()
    # (a program reading our output waits for this line)
  except IOError:
    discard
  if not start and not openBrowser(url):
    g.say osErr, "note: could not open a browser; open the address above\n"

proc serveWeb*(
    g: Globals, command: string, o: WebOptions, cacheDir, path, query: string
): int =
  ## `cacheDir` is the cache directory: the token is kept there, and what is served is in its `user/` part.  If a server of
  ## ours answers on the port, open the page there and return; else serve until stopped (`--stop`, or Ctrl-C, which ends
  ## the process with status 130).  `path` is the address without its first slash ("map/climbs") and `query` what it says
  ## about the look of the page, e.g. "hourly=1" (empty: the defaults).
  let name = "nch " & command
  let args = workerOptions(g)
  let identity = serverIdentity(args)
  if o.port != 0:
    let known = loadToken(cacheDir, false)
    if known.problem.len > 0:
      return failure(g, name, known.problem)
    let running = ask(o.port, known.token, statusPath)
    if running.isSome:
      if running.get.code == 404:
        return failure(
          g,
          name,
          fmt"a server from an older nch (before --stop) is running on port {o.port}: press Ctrl-C where it runs, or `fuser -k {o.port}/tcp`, then try again",
        )
      if running.get.code != 200:
        return failure(
          g,
          name,
          fmt"something on port {o.port} answers but not to our token (a server started before --new-token?): press Ctrl-C where it runs, or `fuser -k {o.port}/tcp`, or use --port N",
        )
      let theirs = running.get.body.split('\n', maxsplit = 1)
      let mine = identity.split('\n', maxsplit = 1)
      if theirs.len < 2 or theirs[1] != mine[1]:
        let what =
          if theirs.len < 2:
            running.get.body
          else:
            theirs[1]
        return failure(
          g,
          name,
          fmt"a server for another database or user ({what}) is running on port {o.port}: `{name} --stop` it first, or use --port N",
        )
      if o.newToken:
        return failure(
          g,
          name,
          fmt"a server is running on port {o.port}: `{name} --stop` it before making a new token",
        )
      if theirs[0] != mine[0]:
        g.say osErr,
          fmt"note: the server on port {o.port} is from another build ({theirs[0]}): `{name} --stop` it and start again to use this one" &
            "\n"
      showPage(g, pageUrl(o.port, path, query, known.token), o.start)
      if o.start:
        g.say osErr, fmt"(the server was already running, on port {o.port})" & "\n"
      return exitOk
  let t = loadToken(cacheDir, o.newToken)
  if t.problem.len > 0:
    return failure(g, name, t.problem)
  let cfg = ServerConfig(
    token: t.token,
    cacheDir: userDir(cacheDir),
    pages: g.extensions.get(webPage),
    baseArgs: args,
    log: g.log,
    logCommand: command,
    identity: identity,
  )
  exitOnInterrupt()
  let problem = serveForever(
    cfg,
    getAppFilename(),
    o.port,
    proc(port: int) {.closure, raises: [].} =
      showPage(g, pageUrl(port, path, query, t.token), o.start)
      g.say osOut,
        fmt"(the server stays running for the pages of `nch` in this terminal: Ctrl-C or `{name} --stop` stops it)" &
          "\n"
      g.log.log(lvInfo, command, leServed, fmt"listening on 127.0.0.1:{port}"),
  )
  if problem.isNone:
    g.log.log(lvInfo, command, leServed, "stopped (asked to)")
    return exitOk
  failure(
    g,
    name,
    fmt"cannot listen on 127.0.0.1:{o.port}: {problem.get}" & (
      if o.port == defaultPort: " (another program has the port? try --port N)" else: ""
    ),
  )

proc stopWeb*(g: Globals, command: string, port: int, cacheDir: string): int =
  ## `--stop`: ask the server of ours on the port to stop.
  let name = "nch " & command
  let known = loadToken(cacheDir, false)
  if known.problem.len > 0:
    return failure(g, name, known.problem)
  let r = ask(port, known.token, stopPath)
  if r.isNone:
    g.say osErr, fmt"no server is running on port {port}" & "\n"
    exitOk
  elif r.get.code == 404:
    failure(
      g,
      name,
      fmt"the server on port {port} is from an nch that cannot be stopped this way (before --stop): press Ctrl-C where it runs, or `fuser -k {port}/tcp`",
    )
  elif r.get.code != 200:
    failure(
      g,
      name,
      fmt"the server on port {port} does not answer to our token (it was started before --new-token?): press Ctrl-C where it runs, or `fuser -k {port}/tcp`",
    )
  else:
    g.say osErr, fmt"stopped the server on port {port}" & "\n"
    exitOk

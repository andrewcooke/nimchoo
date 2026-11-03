## `nch heatmap --web`: serve the heat map on localhost and open it in the browser.
## The files have already been made (so an empty selection is reported in the terminal,
## not in an empty browser tab); from here on the server runs `nch heatmap --worker`
## for each page request, which finds them again (see serve/handler.nim).

import std/[os, osproc]
import ../cli/common
import ../db/store
import ../serve/[handler, server, token]
import ../ui/[interrupt, logfile, vocabulary]
import ./params

{.push raises: [].}

proc workerOptions(g: Globals): seq[string] =
  ## The global options the worker needs to look at the same data as this process.
  result = @["--db", resolveDbPath(g.dbPath)]
  if g.user.len > 0: result.add @["--user", g.user]

proc openBrowser(url: string): bool =
  ## Ask the desktop to open `url`, without waiting for it and without its chatter.  (The
  ## address is handed to the shell as an argument, not made part of a command line.)
  try:
    discard startProcess("/bin/sh",
      args = @["-c", "xdg-open \"$1\" >/dev/null 2>&1 &", "sh", url], options = {poParentStreams})
    true
  except CatchableError:
    false

proc serveWeb*(g: Globals, p: Params, cacheDir, query: string): int =
  ## Serve until stopped (Ctrl-C ends the process with status 130).  `query` is what
  ## pins the page in the address, e.g. "sel=ab12cd&style=lines&tolerance=5".
  let t = loadToken(cacheDir, p.newToken)
  if t.problem.len > 0: return failure("nch heatmap", t.problem)
  let cfg = ServerConfig(token: t.token, cacheDir: cacheDir, run: runWorker(getAppFilename()),
                         baseArgs: workerOptions(g), log: g.log, logCommand: "heatmap")
  exitOnInterrupt()
  let problem = serveForever(cfg, p.port, proc(port: int) {.closure, raises: [].} =
    let url = "http://127.0.0.1:" & $port & "/heatmap?" & query & "&token=" & t.token
    stdout.say url & "\n(Ctrl-C to stop)\n"
    try: stdout.flushFile()       # (a program reading our output waits for this line)
    except IOError: discard
    g.log.log(lvInfo, "heatmap", leServed, "listening on 127.0.0.1:" & $port)
    if not p.noOpen and not openBrowser(url):
      stderr.say "note: could not open a browser; open the address above\n")
  failure("nch heatmap", "cannot listen on 127.0.0.1:" & $p.port & ": " & problem &
    (if p.port == defaultPort: " (is another `nch heatmap --web` running? try --port N)" else: ""))

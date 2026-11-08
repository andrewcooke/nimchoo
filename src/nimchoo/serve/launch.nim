## `nch COMMAND --web`: serve a command's pages on localhost (127.0.0.1) and open the browser at one.
## The files have already been made (so a problem is reported in the terminal, not in an
## empty browser tab); from here on the server runs `nch COMMAND --worker` for each page
## request, which finds them again (see handler.nim).  Shared by the commands that have pages.

import std/[os, osproc]
import ../cache
import ../cli/common
import ../db/store
import ../ui/[interrupt, logfile, vocabulary]
import ./[handler, request, server, token]

{.push raises: [].}

type WebOptions* = object
  port*: int ## the port (0: any free one)
  noOpen*: bool ## do not open the browser
  newToken*: bool ## make a new secret token (the old bookmarks stop working)

proc workerOptions(g: Globals): seq[string] =
  ## The global options the worker needs to look at the same data as this process.
  result = @["--db", resolveDbPath(g.dbPath)]
  if g.user.len > 0:
    result.add @["--user", g.user]

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
  except CatchableError:
    false

proc serveWeb*(
    g: Globals, command: string, o: WebOptions, cacheDir, query: string
): int =
  ## `cacheDir` is the cache directory: the token is kept there, and what is served is in its
  ## `user/` part.  Serve until stopped (Ctrl-C ends the process with status 130).  `query` is what
  ## pins the page in the address, e.g. "bits=AsBO&check=ab12cd".
  let name = "nch " & command
  let t = loadToken(cacheDir, o.newToken)
  if t.problem.len > 0:
    return failure(name, t.problem)
  let cfg = ServerConfig(
    token: t.token,
    cacheDir: userDir(cacheDir),
    baseArgs: workerOptions(g),
    log: g.log,
    logCommand: command,
  )
  exitOnInterrupt()
  let problem = serveForever(
    cfg,
    getAppFilename(),
    o.port,
    proc(port: int) {.closure, raises: [].} =
      let url =
        "http://localhost:" & $port & "/" & command & "?" & query & "&token=" & t.token
      stdout.say url & "\n(Ctrl-C to stop)\n"
      try:
        stdout.flushFile()
      # (a program reading our output waits for this line)
      except IOError:
        discard
      g.log.log(lvInfo, command, leServed, "listening on 127.0.0.1:" & $port)
      if not o.noOpen and not openBrowser(url):
        stderr.say "note: could not open a browser; open the address above\n"
    ,
  )
  failure(
    name,
    "cannot listen on 127.0.0.1:" & $o.port & ": " & problem & (
      if o.port == defaultPort:
      " (is another `" & name & " --web` running? try --port N)"
      else: ""
    ),
  )

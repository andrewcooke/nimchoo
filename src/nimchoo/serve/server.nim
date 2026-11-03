## The socket loop of the local web server: it listens on 127.0.0.1 only and passes each
## request to `handle` (handler.nim), which decides everything.  Single-threaded: one
## user, and a worker that runs for a moment.

import std/[asyncdispatch, asynchttpserver, httpcore, nativesockets, osproc, streams, strutils]
import ./handler

{.push raises: [].}

proc runWorker*(exe: string): WorkerRunner =
  ## A runner that starts `exe` with the arguments (no shell) and waits for it.
  result = proc(args: seq[string]): WorkerResult {.closure, raises: [].} =
    try:
      let p = startProcess(exe, args = args, options = {})
      defer: p.close()
      result.stdout = p.outputStream.readAll()
      result.stderr = p.errorStream.readAll()
      result.code = p.waitForExit(120_000)
    except CatchableError, Defect:
      result = WorkerResult(code: 127, stderr: "cannot run " & exe & ": " & getCurrentExceptionMsg())

{.pop.}   # (the standard library's server and its async callbacks may raise anything)

proc serveForever*(cfg: ServerConfig, port: int,
                   ready: proc(port: int) {.closure, raises: [].}): string {.raises: [].} =
  ## Listen on 127.0.0.1:`port` (0: any free port; `ready` is told which) and answer until
  ## the process is stopped.  Returns what went wrong, if it could not start.
  try:
    let server = newAsyncHttpServer(reuseAddr = true)
    server.listen(Port(port), "127.0.0.1")
    let actual = int(server.getPort)
    proc onRequest(req: Request) {.async, gcsafe.} =
      let incoming = Incoming(
        meth: $req.reqMethod,
        target: req.url.path & (if req.url.query.len > 0: "?" & req.url.query else: ""),
        host: $req.headers.getOrDefault("Host"),
        cookie: $req.headers.getOrDefault("Cookie"))
      var r: Reply
      {.cast(gcsafe).}:      # (one thread: nothing else touches the config or the log)
        r = handle(cfg, actual, incoming)
      await req.respond(HttpCode(r.code), r.body, newHttpHeaders(r.headers))
    ready(actual)
    proc loop() {.async.} =
      while true:
        await server.acceptRequest(onRequest)
    waitFor loop()
  except Exception:
    result = getCurrentExceptionMsg()

## The socket loop of the local web server: it listens on 127.0.0.1 only and passes each
## request to `begin` and `finish` (handler.nim), which decide everything.  One thread and
## an event loop: what is slow is the worker, a child process (`nch COMMAND --worker`), and
## waiting for children does not stop the loop, so requests are answered while workers run.
## (How workers are run, shared and limited: workers.nim.)

import
  std/[asyncdispatch, asynchttpserver, httpcore, nativesockets, strutils]
import ./[handler, workers]

{.push raises: [].}

{.pop.} # (the standard library's server and its async callbacks may raise anything)

proc serveForever*(
    cfg: ServerConfig, exe: string, port: int, ready: proc(port: int) {.closure, raises: [].}
): string {.raises: [].} =
  ## Listen on 127.0.0.1:`port` (0: any free port; `ready` is told which) and answer until
  ## the process is stopped; pages are made by running `exe` (this program) as the worker.
  ## Returns what went wrong, if it could not start.
  try:
    let workers = newWorkers(exe)
    let server = newAsyncHttpServer(reuseAddr = true)
    server.listen(Port(port), "127.0.0.1")
    let actual = int(server.getPort)
    proc onRequest(req: Request) {.async, gcsafe.} =
      let incoming = Incoming(
        meth: $req.reqMethod,
        target: req.url.path & (if req.url.query.len > 0: "?" & req.url.query
        else: ""),
        host: $req.headers.getOrDefault("Host"),
        cookie: $req.headers.getOrDefault("Cookie"),
      )
      var r: Reply
      {.cast(gcsafe).}: # (one thread: nothing else touches the config, the log or the workers)
        let step = begin(cfg, actual, incoming)
        if step.needsWorker:
          let done = await workers.run(step.args)
          r = finish(cfg, incoming, step, done)
        else:
          r = answered(cfg, incoming, step)
      await req.respond(HttpCode(r.code), r.body, newHttpHeaders(r.headers))

    ready(actual)
    proc loop() {.async.} =
      while true:
        await server.acceptRequest(onRequest)

    waitFor loop()
  except Exception: # (the top of the server: whatever ends it is told, not a trace)
    result = getCurrentExceptionMsg()

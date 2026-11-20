## The socket loop of the local web server: it listens on 127.0.0.1 only and passes each
## request to `begin` and `finish` (handler.nim), which decide everything.  One thread and
## an event loop: what is slow is the worker, a child process (`nch COMMAND --worker`), and
## waiting for children does not stop the loop, so requests are answered while workers run.
## (How workers are run, shared and limited: workers.nim.)

import
  std/[asyncdispatch, asynchttpserver, httpcore, nativesockets, strformat, strutils]
import ../../core/logfile
import ./[handler, request, workers]

{.push raises: [].}

type
  ServerEndKind* = enum
    seAsked ## asked to stop (`/stop`)
    seCannotListen ## it never started: the port could not be had
    seFailed ## it was listening and something ended it

  ServerEnd* = object ## Why the server ended.
    case kind*: ServerEndKind
    of seAsked:
      discard
    of seCannotListen, seFailed:
      why*: string

{.pop.} # (the standard library's server and its async callbacks may raise anything)

proc serveForever*(
    cfg: ServerConfig,
    exe: string,
    port: int,
    ready: proc(port: int) {.closure, raises: [].},
): ServerEnd {.raises: [].} =
  ## Listen on 127.0.0.1:`port` (0: any free port; `ready` is told which) and answer until
  ## the process is stopped, or until asked to stop (`/stop`); pages are made by running `exe` (this program)
  ## as the worker.
  var stopping = false
  var listening = false
  try:
    let workers = newWorkers(exe)
    let server = newAsyncHttpServer(reuseAddr = true)
    server.listen(Port(port), "127.0.0.1")
    listening = true
    let actual = int(server.getPort)
    proc onRequest(req: Request) {.async, gcsafe.} =
      let incoming = Incoming(
        meth: $req.reqMethod,
        target: req.url.path & (if req.url.query.len > 0: "?" & req.url.query
        else: ""),
        host: $req.headers.getOrDefault("Host"),
        cookie: $req.headers.getOrDefault("Cookie"),
        token: $req.headers.getOrDefault(tokenHeader),
      )
      # one request that goes wrong (a worker that cannot be started, a browser gone before its reply) is that
      # request's failure, logged; left to rise it would end the loop, and the server with every page it serves
      var r: Reply
      {.cast(gcsafe).}:
        # (one thread: nothing else touches the config, the log or the workers)
        try:
          let step = begin(cfg, actual, incoming)
          if step.needsWorker:
            let done = await workers.run(step.args)
            r = finish(cfg, incoming, step, done)
          else:
            r = answered(cfg, incoming, step)
        except CatchableError as e: # (the top of a request in the server loop)
          cfg.log.log(
            lvError, cfg.logCommand, leFailed, fmt"{incoming.target}: {e.msg}"
          )
          r = reply(500, e.msg)
        try:
          await req.respond(HttpCode(r.code), r.body, newHttpHeaders(r.headers))
        except CatchableError as e: # (the top of a request in the server loop)
          cfg.log.log(
            lvWarn,
            cfg.logCommand,
            leFailed,
            fmt"{incoming.target}: not answered: {e.msg}",
          )
      if r.stop:
        # (the loop is already waiting for the next connection: closing the socket ends the wait)
        stopping = true
        server.close()

    ready(actual)
    proc loop() {.async.} =
      while not stopping:
        await server.acceptRequest(onRequest)

    waitFor loop()
    result = ServerEnd(kind: seAsked)
  except Exception: # (the top of the server: whatever ends it is told, not a trace)
    result =
      if stopping:
        ServerEnd(kind: seAsked)
          # (the wait for a connection, ended by closing the socket)
      elif listening:
        ServerEnd(kind: seFailed, why: getCurrentExceptionMsg())
      else:
        ServerEnd(kind: seCannotListen, why: getCurrentExceptionMsg())

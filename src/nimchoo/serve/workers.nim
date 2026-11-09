## Running the web server's workers (`nch COMMAND --worker`, child processes) for an event loop.  Requests for the same
## page share one run (the same arguments make the same page), at most `maxWorkers` run at once and the others wait
## their turn, and a worker that takes more than `workerTimeoutMs` is killed.  (Not `raises: []`: async code.)

import std/[asyncdispatch, strutils, tables]
import ../childasync
import ./handler

const
  workerTimeoutMs* = 120_000
  maxWorkers* = 4

type Workers* = ref object
  exe: string
  timeoutMs: int
  limit: int
  running: int
  shared: Table[string, Future[WorkerResult]] ## the runs in progress, by their arguments

proc newWorkers*(exe: string, timeoutMs = workerTimeoutMs, limit = maxWorkers): Workers =
  ## A pool that runs `exe` as workers, each within `timeoutMs`, `limit` at once.
  Workers(exe: exe, timeoutMs: timeoutMs, limit: limit)

proc execute(w: Workers, args: seq[string]): Future[WorkerResult] {.async.} =
  ## One run of the worker, when there is room for it.
  while w.running >= w.limit:
    await sleepAsync(20)
  inc w.running
  try:
    let r = await runChildAsync(w.exe, args, w.timeoutMs)
    result = WorkerResult(
      code: r.code,
      stdout: r.stdout,
      stderr:
        if r.timedOut:
          r.stderr & "\nstopped after " & $(w.timeoutMs div 1000) & " s"
        else:
          r.stderr,
    )
  finally:
    dec w.running

proc run*(w: Workers, args: seq[string]): Future[WorkerResult] =
  ## The worker's result for these arguments: a run already going on is waited for, not started again.
  let key = args.join("\x1f")
  if key in w.shared:
    return w.shared[key]
  result = w.execute(args)
  w.shared[key] = result
  result.addCallback(
    proc() =
      w.shared.del(key)
  )

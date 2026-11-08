## `runChild` for an event loop: the same steps (child.nim), but the waiting is `sleepAsync` between looks at the
## child's pipes, so other requests are served meanwhile.  (Not in child.nim: async code is not `raises: []`.)

import std/asyncdispatch
import ./child

const lookEveryMs = 15

proc runChildAsync*(
    exe: string, args: seq[string], timeoutMs: int
): Future[ChildResult] {.async.} =
  ## As `runChild`, without blocking the loop.
  var c = startChild(exe, args, timeoutMs)
  while not c.pump(0):
    await sleepAsync(lookEveryMs)
  while c.busy:
    await sleepAsync(lookEveryMs) # (it closed its outputs, but has not ended)
  return c.settle()

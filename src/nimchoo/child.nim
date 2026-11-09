## Running a child process and collecting what it says: the one way the program does it (the web server runs its
## worker so).  Both outputs are read as they come, so that a child which fills one pipe while the other is waited
## for cannot deadlock; there is a limit on the time, after which the child is killed.  Linux only (it uses `poll`).
##
## `runChild` blocks until the child is done.  The same steps are exported (`startChild`, `pump`, `settle`) for
## `childasync.nim`, which does the waiting without stopping an event loop.

import std/[monotimes, osproc, posix, times]

{.push raises: [].}

const
  notStarted* = 127 ## the exit code when the program could not be run
  timedOutCode* = 124 ## ... and when it was killed for taking too long (as `timeout(1)` says)

type
  ChildResult* = object
    code*: int
    stdout*, stderr*: string
    timedOut*: bool

  Child* = object
    exe: string
    p: Process
    started: bool
    fds: array[2, TPollfd]
    open: int ## the outputs not yet closed
    deadline*: MonoTime
    collected: ChildResult

proc startChild*(exe: string, args: seq[string], timeoutMs: int): Child =
  ## Start `exe` with the arguments (no shell); `timeoutMs` is for the whole run.  If it cannot be started the result
  ## of `settle` says so.
  result.exe = exe
  result.deadline = getMonoTime() + initDuration(milliseconds = timeoutMs)
  try:
    result.p = startProcess(exe, args = args, options = {})
  except OSError, IOError:
    result.collected = ChildResult(
      code: notStarted, stderr: "cannot run " & exe & ": " & getCurrentExceptionMsg()
    )
    return
  result.started = true
  result.fds = [
    TPollfd(fd: cint(result.p.outputHandle), events: POLLIN),
    TPollfd(fd: cint(result.p.errorHandle), events: POLLIN),
  ]
  result.open = 2

proc pump*(c: var Child, waitMs: int): bool =
  ## Read what the child has written, waiting at most `waitMs` for something to come.  True when there is no more to
  ## read: both outputs are closed, or the time is up.
  if not c.started or c.open == 0:
    return true
  let left = (c.deadline - getMonoTime()).inMilliseconds
  if left <= 0:
    c.collected.timedOut = true
    return true
  if poll(addr c.fds[0], Tnfds(2), cint(max(0, min(min(left, int64(waitMs)), 1_000_000)))) > 0:
    var buf: array[16384, char]
    for i in 0 .. 1:
      if c.fds[i].fd >= 0 and (c.fds[i].revents and (POLLIN or POLLHUP or POLLERR)) != 0:
        let got = read(c.fds[i].fd, addr buf[0], buf.len)
        if got > 0:
          var text = newString(got)
          copyMem(addr text[0], addr buf[0], got)
          if i == 0:
            c.collected.stdout.add text
          else:
            c.collected.stderr.add text
        elif got == 0 or errno != EINTR:
          c.fds[i].fd = -1 # (poll skips a negative descriptor)
          dec c.open
  c.open == 0

proc busy*(c: Child): bool =
  ## Still running, and with time left.
  if not c.started or getMonoTime() >= c.deadline:
    return false
  try:
    c.p.running
  except OSError, IOError:
    false

proc waitFor*(c: var Child) =
  ## Wait (blocking) for it to end, within its time.
  if c.started and not c.collected.timedOut:
    try:
      discard c.p.waitForExit(max(1, int((c.deadline - getMonoTime()).inMilliseconds)))
    except OSError, IOError, ValueError:
      discard

proc settle*(c: var Child): ChildResult =
  ## The end of it: the exit code, or, if it is still running (it is past its time, or closed its outputs and carried
  ## on), killed.  What it had written is kept.
  result = c.collected
  if not c.started:
    return
  try:
    if c.p.running:
      c.p.kill()
      discard c.p.waitForExit(2000)
      result.timedOut = true
      result.code = timedOutCode
    elif result.timedOut:
      result.code = timedOutCode # (it ended just as the time was up)
    else:
      result.code = c.p.peekExitCode
  except OSError, IOError, ValueError:
    result.code = notStarted
    result.stderr.add "\ncannot wait for " & c.exe & ": " & getCurrentExceptionMsg()
  try:
    c.p.close()
  except OSError, IOError:
    discard
  c.started = false

proc runChild*(exe: string, args: seq[string], timeoutMs: int): ChildResult =
  ## Run `exe` with the arguments (no shell) and wait for it, at most `timeoutMs` in all; then it is killed, and
  ## whatever it had written is still returned.
  var c = startChild(exe, args, timeoutMs)
  while not c.pump(1000):
    discard
  c.waitFor()
  c.settle()

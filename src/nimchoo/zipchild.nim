## Inflating a zip entry in a child process that cannot use much memory.  zippy has no way to stop at a size (its
## buffer grows as the output does), so an entry whose header says "small" but which inflates to gigabytes would fill
## the machine.  Here the inflating is done by a copy of this program (`nch --inflate IN OUT LIMIT`) that limits its own
## address space before it starts: a runaway entry ends that process (out of memory), not the caller, which says "too
## large".  The compressed bytes go to the child, and the result comes back, in files in a directory of their own.
##
## The caller gives `zipbytes.extractEntry` an `inflateInChild(exe)`; the program's `main` hands `--inflate` to
## `inflateChildMain`.  Linux only (it uses `setrlimit`).

import std/[os, posix, strutils, tempfiles]
import zippy
import ./zipbytes
import ./packages/util/child/child

{.push raises: [].}

const
  inflateFlag* = "--inflate" ## the first argument of the child
  tooLargeCode = 3 ## the child's exit code when the output is over the limit
  damagedCode = 4 ## ... and when the bytes are not a deflate stream
  usageCode = 2
  slackBytes = 512 * 1024 * 1024
    ## address space for the program itself (code, libraries, stacks) on top of the data

let rlimitAs {.importc: "RLIMIT_AS", header: "<sys/resource.h>".}: cint

proc complain(text: string) =
  try:
    stderr.write text & "\n"
  except IOError:
    discard

proc inflateChildMain*(args: seq[string]): int =
  ## The child: `IN OUT LIMIT` (the deflated file, where to write the result, the most it may come to).  0 if all went
  ## well; 3 if it came to more than the limit; 4 if the bytes are damaged; anything else (a signal, 1) if it ran out of
  ## memory.
  if args.len != 3:
    complain "usage: nch " & inflateFlag & " IN OUT LIMIT"
    return usageCode
  var limit = 0
  try:
    limit = parseInt(args[2])
  except ValueError:
    return usageCode
  # zippy doubles its buffer as it grows, and holds the input: three times the limit is more than it needs
  let ceiling = 3 * limit + slackBytes
  var rl = RLimit(rlim_cur: ceiling, rlim_max: ceiling)
  discard setrlimit(rlimitAs, rl)
  try:
    let data = uncompress(readFile(args[0]), dfDeflate)
    if data.len > limit:
      return tooLargeCode
    writeFile(args[1], data)
  except ZippyError, IOError:
    complain "cannot inflate: " & getCurrentExceptionMsg()
    return damagedCode
  0

proc inflateInChild*(exe: string, timeoutMs = 300_000): Inflater =
  ## An `Inflater` that runs `exe` (this program) to do the work.
  result = proc(raw: string, size, limit: int): string {.closure, raises: [ZipError].} =
    var dir = ""
    try:
      dir = createTempDir("nch-inflate-", "")
    except OSError, IOError:
      raiseZip("cannot make a directory to inflate in: " & getCurrentExceptionMsg())
    defer:
      try:
        removeDir(dir)
      except OSError:
        discard
    try:
      writeFile(dir / "in", raw)
    except IOError:
      raiseZip("cannot write to " & dir & ": " & getCurrentExceptionMsg())
    let r = runChild(exe, @[inflateFlag, dir / "in", dir / "out", $limit], timeoutMs)
    if r.timedOut:
      raiseZip("inflating took too long")
    case r.code
    of 0:
      discard
    of tooLargeCode:
      raiseZip("zip entry too large")
    of damagedCode:
      raiseZip(r.stderr.strip)
    of notStarted:
      raiseZip(r.stderr.strip)
    else:
      raiseZip(
        "zip entry too large, or the inflating failed (exit " & $r.code & "): " &
          r.stderr.strip
      )
    try:
      result = readFile(dir / "out")
    except IOError:
      raiseZip("cannot read the inflated entry: " & getCurrentExceptionMsg())

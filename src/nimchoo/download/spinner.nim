## The line that shows a download, drawn by a thread of its own so that it turns while the program waits for the
## network or for the file to be read:
##
##     need locations in CL: download.geonames.org/export/dump/CL.zip (71.3MB) reading ⠹
##
## The thread owns the terminal: it makes its `Live`, draws about ten frames a second, and at the end leaves the
## line on the screen, takes it away or leaves a failure.  The rest of the program only changes what the line says
## (`setSize`, `setReading`) and stops it.  The two share one small record, with plain numbers and fixed-size text
## (nothing that needs a garbage collector), behind a lock.

import std/[locks, monotimes, os, times, typedthreads]
import ../ui/[live, style]
import ./fetch

{.push raises: [].}

const
  cap = 300                         ## the longest label, address or message that is kept
  frames* = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
  frameMs = 80
  pollMs = 25

type
  Phase* = enum phDownloading, phReading

  Ending* = enum
    enRunning, enKeep, enClear, enFailed
      ## the line goes on; it is left as it is; it is taken away; it is replaced by the red failure message

  Text = array[cap, char]

  Shared = object
    lock: Lock
    ending: Ending
    phase: Phase
    bytes: int64
    label, url, message: Text
    maker: proc(): Live {.nimcall, raises: [].}

  Spinner* = ref object
    shared: ptr Shared
    thread: Thread[ptr Shared]
    running*: bool

func progressLine*(label, url: string, bytes: int64, phase: Phase, frame: int, finished: bool): Line =
  ## The line while a file comes, and after.  The address is grey; `bytes` is the size (0: not known yet, and nothing is
  ## said); while the file is not `finished` the spinner turns with `frame`, and says "reading" once the file has come
  ## and is being read.
  result = @[span("need " & label & ": "), span(shortUrl(url), grey)]
  if bytes > 0: result.add span(" (" & humanBytes(bytes) & ")")
  if not finished:
    if phase == phReading: result.add span(" reading")
    result.add span(" " & frames[frame mod frames.len])

proc put(t: var Text, s: string) =
  let n = min(s.len, cap - 1)
  for i in 0 ..< n: t[i] = s[i]
  t[n] = '\0'

proc get(t: Text): string =
  var n = 0
  while n < cap and t[n] != '\0': inc n
  result = newString(n)
  for i in 0 ..< n: result[i] = t[i]

proc loop(s: ptr Shared) {.thread.} =
  {.cast(gcsafe).}:
    let live = s.maker()
    let start = getMonoTime()
    while true:
      acquire(s.lock)
      let ending = s.ending
      let phase = s.phase
      let bytes = s.bytes
      let label = get(s.label)
      let url = get(s.url)
      let message = get(s.message)
      release(s.lock)
      let frame = int((getMonoTime() - start).inMilliseconds) div frameMs
      case ending
      of enRunning:
        if live.due(): live.show(@[progressLine(label, url, bytes, phase, frame, false)])
      of enKeep:
        live.keep(@[progressLine(label, url, bytes, phase, frame, true)])
        break
      of enClear:
        live.finish()
        break
      of enFailed:
        live.keep(@[@[span("cannot download " & shortUrl(url) & ": " & message, red)]])
        break
      sleep(pollMs)

proc startSpinner*(maker: proc(): Live {.nimcall, raises: [].}, label, url: string, phase = phDownloading): Spinner =
  ## Start drawing the line; `maker` makes the `Live` (in the thread).  If the thread cannot be made nothing is drawn.
  result = Spinner()
  let s = cast[ptr Shared](allocShared0(sizeof(Shared)))
  initLock(s.lock)
  s.maker = maker
  s.phase = phase
  put(s.label, label)
  put(s.url, url)
  result.shared = s
  try:
    createThread(result.thread, loop, s)
    result.running = true
  except ResourceExhaustedError:
    discard

proc setSize*(sp: Spinner, bytes: int64) =
  ## What the line says the size is (the size to come, or the size that came).
  if sp.shared.isNil: return
  acquire(sp.shared.lock)
  sp.shared.bytes = bytes
  release(sp.shared.lock)

proc setReading*(sp: Spinner) =
  ## The file has come and is being read.
  if sp.shared.isNil: return
  acquire(sp.shared.lock)
  sp.shared.phase = phReading
  release(sp.shared.lock)

proc stop*(sp: Spinner, ending: Ending, message = "") =
  ## End the line, as `ending` says, and wait for the thread (a few milliseconds).
  if sp.shared.isNil: return
  acquire(sp.shared.lock)
  sp.shared.ending = ending
  put(sp.shared.message, message)
  release(sp.shared.lock)
  if sp.running:
    joinThread(sp.thread)
    sp.running = false
  deinitLock(sp.shared.lock)
  deallocShared(sp.shared)
  sp.shared = nil

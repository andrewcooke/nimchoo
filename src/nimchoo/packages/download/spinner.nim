## The line that shows a download (and the reading of its file), drawn by a thread of its own so that it turns while the program waits for the
## network or for the file to be read:
##
##     need locations in CL: download.geonames.org/export/dump/CL.zip ⠹
##
## The thread owns the terminal: it makes its `Live`, draws about ten frames a second, and at the end leaves the
## line on the screen, takes it away or leaves a failure.  The rest of the program only changes what the line says
## (`setSize`) and stops it.  The two share one small record, with plain numbers and fixed-size text
## (nothing that needs a garbage collector), behind a lock; so the looks of the line's styles are worked out from the
## theme before the thread starts, and it makes a small theme of its own from them.

import std/[locks, monotimes, os, tables, times, typedthreads]
import ../../core/theme
import ../ui/live
import ../ui/[markup, style, units]
import ./fetch

{.push raises: [].}

const
  cap = 300 ## the longest label, address or message that is kept
  frames* = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
  frameMs = 80
  pollMs = 25

type
  Ending* = enum
    enRunning
    enKeep
    enClear
    enFailed
      ## the line goes on; it is left as it is; it is taken away; it is replaced by the failure message

  Text = array[cap, char]

  LineStyle = enum
    lsPlain
    lsHide
    lsBad

  Shared = object
    lock: Lock
    ending: Ending
    bytes: int64
    label, url, message, text: Text
    looks: array[LineStyle, Look] ## of the styles the line uses, in the theme in force
    maker: proc(theme: Theme): Live {.nimcall, raises: [].}

  Spinner* = ref object
    shared: ptr Shared
    thread: Thread[ptr Shared]
    running*: bool

func progressLine*(
    label, url: string, bytes: int64, frame: int, finished: bool, text = ""
): Line =
  ## The line while a file comes and is read, and after:
  ##
  ##     need locations in CL: download.geonames.org/export/dump/CL.zip ⠹
  ##     need locations in CL: download.geonames.org/export/dump/CL.zip (71.3MB)
  ##
  ## The address is hidden (`hide`).  While the work goes on there is only the spinner, turning with `frame`; the size comes when it
  ## is `finished` (nothing if it is not known: 0).
  ## With `text` the line is that text and the spinner (a job of the command's own, like "naming 1,112 activities").
  result =
    if text.len > 0:
      ~"{text}"
    else:
      ~"need {label}: <hide {shortUrl(url)}>"
  if finished:
    if bytes > 0:
      result.add ~" ({humanBytes(bytes)})"
  else:
    result.add ~" {frames[frame mod frames.len]}"

proc put(t: var Text, s: string) =
  let n = min(s.len, cap - 1)
  for i in 0 ..< n:
    t[i] = s[i]
  t[n] = '\0'

proc get(t: Text): string =
  var n = 0
  while n < cap and t[n] != '\0':
    inc n
  result = newString(n)
  for i in 0 ..< n:
    result[i] = t[i]

proc loop(s: ptr Shared) {.thread.} =
  {.cast(gcsafe).}:
    var theme: Theme
    theme.styles[defaultStyle] = asStyle(s.looks[lsPlain])
    theme.styles["hide"] = asStyle(s.looks[lsHide])
    theme.styles["bad"] = asStyle(s.looks[lsBad])
    let live = s.maker(theme)
    let start = getMonoTime()
    while true:
      acquire(s.lock)
      let ending = s.ending
      let bytes = s.bytes
      let label = get(s.label)
      let url = get(s.url)
      let message = get(s.message)
      let text = get(s.text)
      release(s.lock)
      let frame = int((getMonoTime() - start).inMilliseconds) div frameMs
      case ending
      of enRunning:
        if live.due():
          live.show(@[progressLine(label, url, bytes, frame, false, text)])
      of enKeep:
        live.keep(
          @[
            if message.len > 0:
              plain(message)
            else:
              progressLine(label, url, bytes, frame, true, text)
          ]
        )
        break
      of enClear:
        live.finish()
        break
      of enFailed:
        live.keep(@[failedLine(url, message)])
        break
      sleep(pollMs)

proc startSpinner*(
    maker: proc(theme: Theme): Live {.nimcall, raises: [].},
    theme: Theme,
    label, url: string,
    text = "",
): Spinner =
  ## Start drawing the line in `theme`; `maker` makes the `Live` (in the thread).  If the thread cannot be made nothing is
  ## drawn.
  result = Spinner()
  let s = cast[ptr Shared](allocShared0(sizeof(Shared)))
  initLock(s.lock)
  s.maker = maker
  s.looks = [
    lookOf(theme, @[]),
    lookOf(theme, @[styleName"hide"]),
    lookOf(theme, @[styleName"bad"]),
  ]
  put(s.label, label)
  put(s.url, url)
  put(s.text, text)
  result.shared = s
  try:
    createThread(result.thread, loop, s)
    result.running = true
  except ResourceExhaustedError:
    discard

proc setSize*(sp: Spinner, bytes: int64) =
  ## What the line says the size is (the size to come, or the size that came).
  if sp.shared.isNil:
    return
  acquire(sp.shared.lock)
  sp.shared.bytes = bytes
  release(sp.shared.lock)

proc stop*(sp: Spinner, ending: Ending, message = "") =
  ## End the line, as `ending` says, and wait for the thread (a few milliseconds).  With `enKeep` a `message` is what is
  ## left on the screen, in place of the line; with `enFailed` it is why.
  if sp.shared.isNil:
    return
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

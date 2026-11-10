## A live region of the terminal: a block of lines that is redrawn in place,
## with permanent lines printed above it.  No scrolling, no input.
##
## The caller keeps its own state and asks `due` whether it is time for a
## frame; only then does it render its lines and `show` them, so redrawing is
## throttled however fast events arrive.  Each frame is built as one string and
## written once.  The clock, the terminal size and the writer are parameters,
## so the driver is tested without a terminal.
##
## Escape sequences used: cursor up (ESC [ n A), erase line (ESC [ 2 K), erase
## to the end of the screen (ESC [ J), hide / show cursor (ESC [ ? 25 l / h).

import std/[monotimes, os]
when defined(posix):
  import std/posix
from std/terminal import isatty, terminalWidth, terminalHeight
import ./style

{.push raises: [].}

type
  Write = proc(s: string) {.closure, raises: [].}
  Clock = proc(): int64 {.closure, raises: [].} # milliseconds, monotonic
  Size = proc(): tuple[w, h: int] {.closure, raises: [].}

  Live* = ref object
    write: Write
    now: Clock
    size: Size
    colour: bool
    firstDelay, interval: int64
    startAt, lastDraw: int64
    drawn: int # lines of the region now on screen
    shown: bool # a frame has been drawn: the cursor is hidden
    queued: seq[Line] # permanent lines waiting for the next frame

const
  hideCursor = "\e[?25l"
  showCursor = "\e[?25h"
  eraseLine = "\e[2K"
  eraseBelow = "\e[J"

func up(n: int): string =
  "\e[" & $n & "A"

proc newLive*(
    write: Write,
    now: Clock,
    size: Size,
    colour: bool,
    firstDelay = 150'i64,
    interval = 100'i64,
): Live =
  ## A live region.  The first frame is shown no sooner than `firstDelay` ms
  ## after this call (a short run draws nothing), and then at most one frame
  ## every `interval` ms.
  Live(
    write: write,
    now: now,
    size: size,
    colour: colour,
    firstDelay: firstDelay,
    interval: interval,
    startAt: now(),
  )

proc due*(l: Live): bool =
  ## Whether it is time to show a frame.
  let t = l.now()
  t - l.startAt >= l.firstDelay and (not l.shown or t - l.lastDraw >= l.interval)

proc print*(l: Live, line: Line) =
  ## A permanent line, printed above the region with the next frame (or when
  ## the region is finished).
  l.queued.add line

proc permanent(l: Live, f: var string) =
  for q in l.queued:
    f.add eraseLine & q.render(l.colour) & "\n"
  l.queued.setLen(0)

proc frame(l: Live, lines: seq[Line]): string =
  ## The text that draws `lines` as the region now: queued permanent lines
  ## first.  The region is cut to the terminal's height and each of its lines
  ## to its width.
  let (w, h) = l.size()
  let shownLines = lines[0 ..< min(lines.len, max(0, h - 1))]
  var f = ""
  if not l.shown:
    f.add hideCursor
    l.shown = true
  if l.drawn > 0:
    f.add up(l.drawn)
  l.permanent(f)
  for ln in shownLines:
    f.add eraseLine & ln.truncated(w - 1).render(l.colour) & "\n"
  f.add eraseBelow
  l.drawn = shownLines.len
  l.lastDraw = l.now()
  f

proc show*(l: Live, lines: seq[Line]) =
  ## Draw a frame now.
  l.write l.frame(lines)

proc keep*(l: Live, lines: seq[Line]) =
  ## End the display with `lines` as its last frame, left on screen, and give
  ## the cursor back.  Drawn even if no frame was due (or ever shown).
  l.write l.frame(lines) & showCursor
  l.drawn = 0
  l.shown = false

proc finish*(l: Live) =
  ## End the display, removing the region: print what is still queued, and
  ## give the cursor back.  (`keep` leaves the region instead.)
  var f = ""
  if l.drawn > 0:
    f.add up(l.drawn)
  l.permanent(f)
  f.add eraseBelow
  if l.shown:
    f.add showCursor
  l.drawn = 0
  l.shown = false
  l.write f

# --- the real terminal

proc canLive*(): bool =
  ## Whether a live display makes sense: stderr is a terminal that is not "dumb".
  isatty(stderr) and getEnv("TERM") != "dumb"

proc canColourStdout*(): bool =
  ## Whether to colour what goes to stdout: it is a terminal that is not "dumb",
  ## and NO_COLOR (no-color.org) is not set.
  isatty(stdout) and getEnv("TERM") != "dumb" and getEnv("NO_COLOR").len == 0

proc canColour*(): bool =
  ## Whether to use colours: a live display, and NO_COLOR (no-color.org) unset.
  canLive() and getEnv("NO_COLOR").len == 0

func orDefault(n, default: int): int =
  ## A terminal that does not report its size reports 0.
  if n > 0: n else: default

const pipedHelpWidth* = 120 ## the width of help text that is not going to a terminal

proc helpWidth*(f: File): int =
  ## How wide the help text may be on `f`: the width of the terminal if it is one (80 if it will not say), else
  ## `pipedHelpWidth`, for a file or a pipe has no width.
  if isatty(f) and getEnv("TERM") != "dumb":
    orDefault(terminalWidth(), 80)
  else:
    pipedHelpWidth

proc restoreCursor() {.noconv.} =
  ## Ctrl-C: give the terminal back, then stop.  (The handler cannot see any
  ## Live, so it shows the cursor whether or not it was hidden.)
  try:
    stderr.write showCursor & "\n"
  except IOError:
    discard
  when defined(posix):
    exitnow(130) # (`quit` in a signal handler ends with status 127)
  else:
    quit(130)

proc newTerminalLive*(): Live =
  ## A live region on stderr, using the real clock and terminal size.
  setControlCHook(restoreCursor)
  newLive(
    write = proc(s: string) {.closure, raises: [].} =
      try:
        stderr.write s
        stderr.flushFile
      except IOError:
        discard,
    now = proc(): int64 {.closure, raises: [].} =
      getMonoTime().ticks div 1_000_000,
    size = proc(): tuple[w, h: int] {.closure, raises: [].} =
      (orDefault(terminalWidth(), 80), orDefault(terminalHeight(), 24)),
    colour = canColour(),
  )

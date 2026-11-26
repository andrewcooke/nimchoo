## What every view (`map`, `plot`, `calendar`) does with the subjects and their frames, written once: choosing the
## subject, choosing the frames (`--frames`, else those shown unless told otherwise), the usage's table of the subjects and
## their frames, and stopping, with a warning, when the selection a frame is made from is empty.  The frames are each
## view's own type (`MapFrame`, `PlotFrame`): anything with `subject`, `name`, `summary` and `shown`.

import std/[options, sequtils, strutils]
import ../../core/[errors, globals, line]
import ../../core/markup
import ../util/args/[args, usage]
import ../user/session
import ./subjects

{.push raises: [].}

proc chooseSubject*(
    all: seq[Subject], asked: Option[string], view: string
): Parsed[Subject] =
  ## The subject asked for (the default one if none was), or what is wrong: `view` is "a map", "a plot" ...
  let subject = findSubject(all, asked)
  if subject.isNone:
    return problemWith[Subject](noSubject(all, asked, view))
  parsedOk(subject.get)

func notAFrame*(name, subject: string, frames: seq[string]): Line =
  ## "'heat' is not a frame of climbs (the frames are ...)".
  let names = frames.join(", ")
  ~"'{name}' is not a frame of {subject} (the frames are {names})"

func chooseFrames*[T](
    all: seq[T], subject: string, wanted: seq[string], view: string
): Parsed[seq[T]] =
  ## The frames of `subject` asked for, in the order asked (each once); with none asked for, those shown unless told
  ## otherwise (all of them if none is); or what is wrong.  `view` is "a map", "a plot" ...
  let mine = all.filterIt(it.subject == subject)
  if mine.len == 0:
    return problemWith[seq[T]](~"no frame of {subject} can be shown on {view}")
  if wanted.len == 0:
    let shown = mine.filterIt(it.shown)
    return parsedOk(if shown.len > 0: shown else: mine)
  var chosen: seq[T]
  for want in wanted:
    let there = mine.filterIt(it.name == want)
    if there.len == 0:
      return problemWith[seq[T]](notAFrame(want, subject, mine.mapIt(it.name)))
    if chosen.allIt(it.name != want):
      chosen.add there[0]
  parsedOk(chosen)

func frameTable*[T](subjects: seq[Subject], all: seq[T], width: int): seq[Line] =
  ## The subjects and their frames, as a table for a usage (from the registry), and what the marks mean.
  var rows: seq[seq[Line]]
  var default = ""
  for s in subjects:
    if s.isDefault:
      default = s.name
    for f in all.filterIt(it.subject == s.name):
      rows.add @[
        plain(s.name), plain(f.name & (if f.shown: "*" else: "")), plain(f.summary)
      ]
  if rows.len == 0:
    return
  result = tableLines(@["subject", "frame", "what it is"], rows, width)
  result.add plain("")
  result.add (
    ~"* drawn when `--frames` is not given; the subject is {default} when none is given."
  ).wrapped(width)

proc stopIfEmpty*(
    g: Globals, st: Session, subject: Subject, reads: bool
): Option[int] {.raises: [StoreError].} =
  ## Whether to stop, and with what status, before a view is made: an empty selection (if what is shown reads it) is said
  ## as a warning and stops with success, since nothing to show is no failure; none: go on.
  if reads and subject.selected(st) == 0:
    g.warn emptyText(subject)
    return some(exitOk)

proc stopIfEmpty*(
    g: Globals, subject: Subject, reads: bool, command: string
): Option[int] =
  ## The same, in a session of its own (for a view that has none open yet); a failure of the database is reported.
  if not reads:
    return
  var st: Session
  try:
    st = openSession(g)
  except StoreError as e:
    return some(failure(g, command, e.msg))
  try:
    stopIfEmpty(g, st, subject, reads)
  except StoreError as e:
    some(failure(g, command, e.msg))
  finally:
    st.close()

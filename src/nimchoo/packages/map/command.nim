## `nch map [SUBJECT]`: a subject on a map.  The map is a view (it knows no subject): the packages that manage a
## subject contribute the frames of it (`map/frames`: the routes of the selected activities, the climbs they went up ...), each
## made as a GeoJSON file of its own in the cache directory (every feature says what it is, in `kind`, and nothing about how it
## looks), and a page, drawn by Leaflet in the browser, decides the look: each frame has a style of its own, which its provider ships.
##
## A map is a live view: it shows the selection of the subject as it is when a frame is made, and each is made again whenever it is
## shown.  The page is the subject's (`/map/activities`, `map-activities.html`) and lists every frame of it; the frames ticked
## are fetched from the same address with `?frame=NAME` (the worker with `--frame`), and the browser remembers which are ticked.
## The files are named by the subject and the frame (`map-activities-routes.geojson`); `--file` makes those of `--frames`.
##
## This module is above `subject`: it reads the registry of subjects and of frames, and nothing of the packages that provide them.

import std/[options, sequtils, strformat, strutils]
import ../cache/cache
import ../util/atomic/atomic
import ../../core/[extension, globals]
import ../../core/errors
import ../subject/subjects
import ../ui/live
import ../util/args/[args, usage]
import ../web/launch
import ../web/pages
import ../web/webopts
import ./[frames, page, params]
import ../db/store
import ../user/session

{.push raises: [].}

const commandName* = "map" ## what the user types after `nch`

proc options*(g: Globals): seq[OptDoc] {.nimcall, raises: [].} =
  ## The options of `nch map`, described (for tab completion).
  mapSpec().docs

const
  synopsis =
    "usage: nch [--db PATH] [--user NAME] map [SUBJECT] [--file [--frames FRAME...] | --stop | [--start] [--port N] [--new-token]]"
  intro =
    """Show a subject on a map: by default the activities of the selection (see `nch activities --select`).  What is drawn are
the subject's frames, the layers in the table below, each made by the package that knows about it: the page lists them, and you
tick the ones to draw (the browser remembers them for the next time; at first, those marked *).  It serves the page on
localhost and opens it in a browser (Ctrl-C stops it); with --file it makes a GeoJSON file for each frame (those of --frames)
in the cache directory instead, and prints where.  A click on anything drawn says what it is."""
  notes =
    """A frame is made from the data as they are when it is shown: reload the page to see the selection as it is now.  The
address of the page is the subject's (/map/activities), so a bookmark keeps the subject, not the activities."""

func registryLines(
    subjects: seq[Subject], all: seq[MapFrame], width: int
): seq[string] =
  ## The subjects and their frames, as a table (from the registry), and what the marks mean.
  var rows: seq[seq[string]]
  var default = ""
  for s in subjects:
    if s.isDefault:
      default = s.name
    for f in framesOf(all, s.name):
      rows.add @[s.name, f.name & (if f.shown: "*" else: ""), f.summary]
  if rows.len == 0:
    return
  result = tableLines(@["subject", "frame", "what it is"], rows, width)
  result.add ""
  result.add wrap(
    fmt"* drawn when --frames is not given; the subject is {default} when none is given.",
    width,
  )

proc usageText*(g: Globals, width: int): string =
  ## The usage: the synopsis, the introduction, the options and the subjects with their frames, wrapped to `width`.
  synopsis & "\n\n" & prose(intro, width) & "\n\n" & prose(notes, width) & "\n\n" &
    optionLines(mapSpec().docs, width).join("\n") & "\n\n" &
    registryLines(
      g.extensions.get(subjectPoint), g.extensions.get(mapFramePoint), width
    )
    .join("\n") & "\n"

type Chosen = object
  subject: Subject
  frames: seq[MapFrame] ## what is drawn, in order

proc choose(g: Globals, p: Params): Parsed[Chosen] =
  ## The subject and frames the command line asks for, or what is wrong with them (the registry says what exists).
  let all = g.extensions.get(subjectPoint)
  if all.len == 0:
    return problemWith[Chosen]("no subject can be shown on a map")
  let name = p.subject.get(defaultSubject(all).name)
  var chosen: Chosen
  var found = false
  for s in all:
    if s.name == name:
      chosen.subject = s
      found = true
  if not found:
    let names = all.mapIt(it.name).join(", ")
    return problemWith[Chosen](fmt"no subject '{name}' (the subjects are {names})")
  let mine = framesOf(g.extensions.get(mapFramePoint), name)
  if mine.len == 0:
    return problemWith[Chosen](fmt"no frame of {name} can be shown on a map")
  let names = mine.mapIt(it.name).join(", ")
  if p.frames.len == 0:
    for f in mine:
      if f.shown:
        chosen.frames.add f
    if chosen.frames.len == 0:
      chosen.frames = mine
    return parsedOk(chosen)
  for want in p.frames:
    let there = mine.filterIt(it.name == want)
    if there.len == 0:
      return problemWith[Chosen](
        fmt"'{want}' is not a frame of {name} (the frames are {names})"
      )
    if there[0] notin chosen.frames:
      chosen.frames.add there[0]
  parsedOk(chosen)

func fileStem(subject, frame: string): string =
  ## What the file of a frame is named: `map-activities-routes`.
  fmt"map-{subject}-{frame}"

func readsSelection(c: Chosen): bool =
  ## Whether some chosen frame is made from the selection (the others need it not to be empty no more than they need anything).
  c.frames.anyIt(it.readsSelection)

proc emptyFailure(g: Globals, s: Subject): int =
  failure(g, "nch map", fmt"the selection of {s.name} is empty ({s.emptyHint})")

proc checkSelection(g: Globals, c: Chosen): int =
  ## The selection is not empty, if a chosen frame reads it (before serving, and before making the page).
  var st: Session
  try:
    st = openSession(g)
  except StoreError as e:
    return failure(g, "nch map", e.msg)
  try:
    if readsSelection(c) and c.subject.selected(st) == 0:
      return emptyFailure(g, c.subject)
    exitOk
  except StoreError as e:
    failure(g, "nch map", e.msg)
  finally:
    st.close()

proc makeFrames(
    g: Globals, c: Chosen, frames: seq[MapFrame], dir: string
): tuple[paths: seq[string], status: int] =
  ## Make the file of each frame, whatever was there, from the data as they are now (in one read transaction, so that the
  ## frames are made from one state of the database).  Reports problems.
  var st: Session
  try:
    st = openSession(g)
  except StoreError as e:
    return (@[], failure(g, "nch map", e.msg))
  try:
    var made: seq[FrameData]
    st.begin()
    try:
      if frames.anyIt(it.readsSelection) and c.subject.selected(st) == 0:
        return (@[], emptyFailure(g, c.subject))
      for f in frames:
        made.add f.make(st)
    finally:
      st.rollback()
    for k, f in frames:
      for note in made[k].notes:
        g.say osErr, fmt"note: {note}" & "\n"
      let path = cacheFile(dir, fileStem(c.subject.name, f.name), "geojson").get
      writeAtomic(path, made[k].geojson)
      result.paths.add path
  except StoreError as e:
    result = (@[], failure(g, "nch map", e.msg))
  except IOError, OSError:
    result = (
      @[], failure(g, "nch map", fmt"cannot write to {dir}: {getCurrentExceptionMsg()}")
    )
  finally:
    st.close()

proc makePage(g: Globals, c: Chosen, dir: string): tuple[page: string, status: int] =
  ## Make the page: every frame of the subject, those shown by default ticked (it fetches the data of each frame it shows).
  let checked = checkSelection(g, c)
  if checked != exitOk:
    return ("", checked)
  try:
    let all = framesOf(g.extensions.get(mapFramePoint), c.subject.name)
    var listed: seq[tuple[frame: MapFrame, shown: bool]]
    for f in all:
      listed.add (f, f.shown) # (at first; the browser remembers what is ticked)
    let path = cacheFile(dir, fmt"map-{c.subject.name}", "html").get
    writeAtomic(path, pageHtml(listed, c.subject.name, "Map"))
    result = (path, exitOk)
  except IOError, OSError:
    result = (
      "", failure(g, "nch map", fmt"cannot write to {dir}: {getCurrentExceptionMsg()}")
    )
  except TemplateError as e:
    result = (
      "",
      failure(
        g,
        "nch map",
        fmt"cannot make the page: {e.msg} (the templates are in system/templates/ and the libraries are system/libraries.txt, in the cache directory; delete one to have the built-in one again)",
      ),
    )

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch map ARGS`; returns the exit status.
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    g.say osOut, usageText(g, helpWidth(stdout))
    return exitOk
  of pkProblem:
    return usageError(g, "nch map", usageText(g, helpWidth(stderr)), parsed.problem)
  of pkOk:
    discard
  let p = parsed.params
  let chosen = choose(g, p)
  if chosen.kind != pkOk:
    return usageError(g, "nch map", usageText(g, helpWidth(stderr)), chosen.problem)
  let c = chosen.params
  let dir = cacheDir()
  if dir.isNone:
    return failure(g, "nch map", "no place for the cache: set NCH_CACHE or HOME")
  try:
    makeCacheDirs(dir.get)
  except IOError, OSError:
    return failure(g, "nch map", fmt"cannot make {dir.get}: {getCurrentExceptionMsg()}")
  case p.web.kind
  of wkStop:
    return stopWeb(g, commandName, p.web.stopPort, dir.get)
  of wkServe:
    let checked = checkSelection(g, c)
    if checked != exitOk:
      return checked
    # the address keeps the look (the frames); the data are those of the selection when the page is asked for
    return serveWeb(
      g,
      commandName,
      WebOptions(port: p.web.port, start: p.web.start, newToken: p.web.newToken),
      dir.get,
      commandName & "/" & c.subject.name,
      "",
    )
  of wkWorker:
    if p.frame.isSome:
      # the data of one frame, which the page fetches
      let one = framesOf(g.extensions.get(mapFramePoint), c.subject.name).filterIt(
          it.name == p.frame.get
        )
      if one.len == 0:
        return usageError(
          g,
          "nch map",
          usageText(g, helpWidth(stderr)),
          fmt"'{p.frame.get}' is not a frame of {c.subject.name}",
        )
      let made = makeFrames(g, c, one, userDir(dir.get))
      if made.status != 0:
        return made.status
      g.say osOut, made.paths[0] & "\n"
    else:
      let made = makePage(g, c, userDir(dir.get))
      if made.status != 0:
        return made.status
      g.say osOut, made.page & "\n"
  of wkFile:
    let made = makeFrames(g, c, c.frames, userDir(dir.get))
    if made.status != 0:
      return made.status
    g.say osOut, made.paths.join("\n") & "\n"
  exitOk

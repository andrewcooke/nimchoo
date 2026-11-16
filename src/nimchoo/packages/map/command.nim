## `nch map [SUBJECT] [--frames FRAME...]`: a subject on a map.  The map is a view (it knows no subject): the packages that manage a
## subject contribute the frames of it (`map/frames`: the routes of the selected activities, the climbs they went up ...), each
## made as a GeoJSON file of its own in the cache directory (every feature says what it is, in `kind`, and nothing about how it
## looks), and a page, drawn by Leaflet in the browser, decides the look: each frame has a style of its own, which its provider ships.
##
## A map is a live view: it shows the selection of the subject as it is when the map is made, and is made again for every request.
## The files are named by the subject and the frame (`map-activities-routes.geojson`); a bookmark of the page
## (`/map/activities?frames=routes,climbs`) keeps the look, not the data.
##
## This module is above `subject`: it reads the registry of subjects and of frames, and nothing of the packages that provide them.

import std/[options, os, sequtils, strformat, strutils]
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
    "usage: nch [--db PATH] [--user NAME] map [SUBJECT] [--frames FRAME...] [--file | [--no-open] [--port N] [--new-token]]"
  intro =
    """Show a subject (by default the activities: see `nch activities --select`) on a map.  What is drawn are its frames: for the
activities by default their routes and the climbs they went up, drawn over them; `heat` shows how often each place was visited, in
cells (about 100 m, coarser as you zoom out).  It serves a page that draws them on localhost and opens it in a browser (Ctrl-C
stops it); with --file it makes a GeoJSON file for each frame in the cache directory instead and prints their paths.  Several rides
over the same roads show as a glow; a click on a route says which activity it is, a click on a climb says what it is, a click on a
cell says how often it was visited.  Climbs are worked out by the import and `nch climbs`; a map says when some activities have none."""
  notes =
    """The map is made again each time the page is loaded, from the selection as it is then: a bookmark of the address keeps
which frames are drawn, not which activities."""

func registryText(subjects: seq[Subject], all: seq[MapFrame]): string =
  ## The subjects and the frames each has, as the usage says them.
  for s in subjects:
    result.add "\n" & s.name & (if s.isDefault: " (the default)" else: "") & ": " &
      s.summary & "\n"
    for f in framesOf(all, s.name):
      result.add "  " & f.name & (if f.shown: " *" else: "") & ": " & f.summary & "\n"
  if result.len > 0:
    result.add "\n(* is drawn when --frames is not given)\n"

proc usageText*(g: Globals, width: int): string =
  ## The usage: the synopsis, the introduction, the options and the subjects with their frames, wrapped to `width`.
  synopsis & "\n\n" & prose(intro, width) & "\n\n" & prose(notes, width) & "\n\n" &
    optionLines(mapSpec().docs, width).join("\n") & "\n" &
    registryText(g.extensions.get(subjectPoint), g.extensions.get(mapFramePoint))

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

proc emptyFailure(s: Subject): int =
  failure("nch map", fmt"the selection of {s.name} is empty ({s.emptyHint})")

proc prepare(
    g: Globals, c: Chosen, dir: string, withPage: bool
): tuple[paths: seq[string], page: string, status: int] =
  ## Make the file of each frame (and, if asked, the page), whatever was there, from the data as they are now.  Reports problems.
  var st: Session
  try:
    st = openSession(g)
  except StoreError as e:
    return (@[], "", failure("nch map", e.msg))
  try:
    # one read transaction: the frames are made from one state of the database, whatever else is writing
    var made: seq[FrameData]
    st.begin()
    try:
      if readsSelection(c) and c.subject.selected(st) == 0:
        return (@[], "", emptyFailure(c.subject))
      for f in c.frames:
        made.add f.make(st)
    finally:
      st.rollback()
    var names: seq[string]
    for k, f in c.frames:
      for note in made[k].notes:
        stderr.say fmt"note: {note}" & "\n"
      let stem = fileStem(c.subject.name, f.name)
      let path = cacheFile(dir, stem, "geojson").get
      writeAtomic(path, made[k].geojson)
      result.paths.add path
      names.add f.name
    if withPage:
      let stem = fileStem(c.subject.name, names.join("-"))
      let pagePath = cacheFile(dir, stem, "html").get
      let html = pageHtml(
        result.paths.mapIt(extractFilename(it)), "Map", g.extensions.get(mapFramePoint)
      )
      if html.isNone:
        return
          (@[], "", failure("nch map", fmt"cannot make a page for {result.paths[0]}"))
      writeAtomic(pagePath, html.get)
      result.page = pagePath
  except StoreError as e:
    result = (@[], "", failure("nch map", e.msg))
  except IOError, OSError:
    result = (
      @[],
      "",
      failure("nch map", fmt"cannot write to {dir}: {getCurrentExceptionMsg()}"),
    )
  except TemplateError as e:
    result = (
      @[],
      "",
      failure(
        "nch map",
        fmt"cannot make the page: {e.msg} (the templates are in system/templates/ and the libraries are system/libraries.txt, in the cache directory; delete one to have the built-in one again)",
      ),
    )
  finally:
    st.close()

proc checkSelection(g: Globals, c: Chosen): int =
  ## Before serving: the selection is not empty (the page makes the files, whenever it is asked for).
  var st: Session
  try:
    st = openSession(g)
  except StoreError as e:
    return failure("nch map", e.msg)
  try:
    if readsSelection(c) and c.subject.selected(st) == 0:
      return emptyFailure(c.subject)
    exitOk
  except StoreError as e:
    failure("nch map", e.msg)
  finally:
    st.close()

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch map ARGS`; returns the exit status.
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    stdout.say usageText(g, helpWidth(stdout))
    return exitOk
  of pkProblem:
    return usageError("nch map", usageText(g, helpWidth(stderr)), parsed.problem)
  of pkOk:
    discard
  let p = parsed.params
  let chosen = choose(g, p)
  if chosen.kind != pkOk:
    return usageError("nch map", usageText(g, helpWidth(stderr)), chosen.problem)
  let c = chosen.params
  let dir = cacheDir()
  if dir.isNone:
    return failure("nch map", "no place for the cache: set NCH_CACHE or HOME")
  try:
    makeCacheDirs(dir.get)
  except IOError, OSError:
    return failure("nch map", fmt"cannot make {dir.get}: {getCurrentExceptionMsg()}")
  case p.web.kind
  of wkServe:
    let checked = checkSelection(g, c)
    if checked != exitOk:
      return checked
    # the address keeps the look (the frames); the data are those of the selection when the page is asked for
    return serveWeb(
      g,
      commandName,
      WebOptions(port: p.web.port, noOpen: p.web.noOpen, newToken: p.web.newToken),
      dir.get,
      commandName & "/" & c.subject.name,
      "frames=" & c.frames.mapIt(it.name).join(","),
    )
  of wkWorker:
    let made = prepare(g, c, userDir(dir.get), true)
    if made.status != 0:
      return made.status
    stdout.say made.page & "\n" & made.paths.join("\n") & "\n"
  of wkFile:
    let made = prepare(g, c, userDir(dir.get), false)
    if made.status != 0:
      return made.status
    stdout.say made.paths.join("\n") & "\n"
  exitOk

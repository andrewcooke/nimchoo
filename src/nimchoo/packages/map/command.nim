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

import std/[options, sequtils, strformat]
import ../cache/cache
import ../util/atomic/atomic
import ../../core/[extension, globals]
import ../../core/errors
import ../subject/[subjects, views]
import ../ui/[style]
import ../util/args/[args, usage]
import ../web/pages
import ../web/view
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
  intro = @[
    ~"Show a subject on a map: by default the activities of the selection (see `nch activities --select`).  What is drawn are the subject's frames, the layers in the table below, each made by the package that knows about it: the page lists them, and you tick the ones to draw (the browser remembers them for the next time; at first, those marked *).  It serves the page on localhost and opens it in a browser (one server serves every page, and keeps running after the command returns: `--stop` stops it); with `--file` it makes a GeoJSON file for each frame (those of `--frames`) in the cache directory instead, and prints where.  A click on anything drawn says what it is."
  ]
  notes = @[
    ~"A frame is made from the data as they are when it is shown: reload the page to see the selection as it is now.  The address of the page is the subject's (/map/activities), so a bookmark keeps the subject, not the activities."
  ]

proc usageText*(g: Globals, width: int): seq[Line] =
  ## The usage: the synopsis, the introduction, the options and the subjects with their frames, wrapped to `width`.
  usageOf(
    synopsis,
    width,
    intro,
    mapSpec().docs,
    notes,
    @[
      (
        "subjects and frames",
        frameTable(
          g.extensions.get(subjectPoint), g.extensions.get(mapFramePoint), width
        ),
      )
    ],
  )

type Chosen = object
  subject: Subject
  frames: seq[MapFrame] ## what is drawn, in order

proc choose(g: Globals, p: Params): Parsed[Chosen] =
  ## The subject and frames the command line asks for, or what is wrong with them (the registry says what exists).
  let subject = chooseSubject(g.extensions.get(subjectPoint), p.subject, "a map")
  if subject.kind != pkOk:
    return problemWith[Chosen](subject.why)
  let frames = chooseFrames(
    g.extensions.get(mapFramePoint), subject.params.name, p.frames, "a map"
  )
  if frames.kind != pkOk:
    return problemWith[Chosen](frames.why)
  parsedOk(Chosen(subject: subject.params, frames: frames.params))

func fileStem(subject, frame: string): string =
  ## What the file of a frame is named: `map-activities-routes`.
  fmt"map-{subject}-{frame}"

proc makeFrames(g: Globals, c: Chosen, frames: seq[MapFrame], dir: string): Made =
  ## Make the file of each frame, whatever was there, from the data as they are now (in one read transaction, so that the
  ## frames are made from one state of the database).  Reports problems.
  var st: Session
  try:
    st = openSession(g)
  except StoreError as e:
    return Made(status: failure(g, "nch map", e.msg))
  try:
    var made: seq[FrameData]
    st.beginRead()
    try:
      for f in frames:
        made.add f.make(st)
    finally:
      st.rollback()
    for k, f in frames:
      for w in made[k].warnings:
        g.warn w
      let path = cacheFile(dir, fileStem(c.subject.name, f.name), "geojson").get
      writeAtomic(path, made[k].geojson)
      result.paths.add path
  except StoreError as e:
    result = Made(status: failure(g, "nch map", e.msg))
  except IOError, OSError:
    result = Made(status: cannotWrite(g, "nch map", dir))
  finally:
    st.close()

proc makePage(g: Globals, c: Chosen, dir: string): Made =
  ## Make the page: every frame of the subject, those shown by default ticked (it fetches the data of each frame it shows).
  try:
    let listed = framesOf(g.extensions.get(mapFramePoint), c.subject.name)
    let path = cacheFile(dir, fmt"map-{c.subject.name}", "html").get
    writeAtomic(path, pageHtml(listed, c.subject.name, "Map"))
    result = Made(paths: @[path])
  except IOError, OSError:
    result = Made(status: cannotWrite(g, "nch map", dir))
  except TemplateError as e:
    result = Made(status: templateFailure(g, "nch map", e.msg))

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch map ARGS`; returns the exit status.
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    g.showAll osOut, usageText(g, g.textWidth(osOut))
    return exitOk
  of pkProblem:
    return usageError(g, "nch map", usageText(g, g.textWidth(osErr)), parsed.why)
  of pkUnit:
    return unitRetry(g, "nch map", parsed.fix, run)
  of pkOk:
    discard
  let p = parsed.params
  let chosen = choose(g, p)
  if chosen.kind != pkOk:
    return usageError(g, "nch map", usageText(g, g.textWidth(osErr)), chosen.problem)
  let c = chosen.params
  runView(
    g,
    p.web,
    View(
      command: commandName,
      address: commandName & "/" & c.subject.name,
      # (the address keeps the subject; the data are those of the selection when the page is asked for)
      nothing: proc(): Option[int] =
        stopIfEmpty(g, c.subject, c.frames.anyIt(it.readsSelection), "nch map"),
      page: proc(dir: string): Made =
        makePage(g, c, dir),
      frame: proc(name, dir: string): Made =
        # the data of one frame, which the page fetches
        let one = chooseFrames(
          g.extensions.get(mapFramePoint), c.subject.name, @[name], "a map"
        )
        if one.kind != pkOk:
          return Made(
            status: usageError(g, "nch map", usageText(g, g.textWidth(osErr)), one.why)
          )
        makeFrames(g, c, one.params, dir),
      files: proc(dir: string): Made =
        makeFrames(g, c, c.frames, dir),
      frameAsked: p.frame,
    ),
  )

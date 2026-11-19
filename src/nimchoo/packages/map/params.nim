## The command line of `nch map`, parsed.  Pure.  `nch map [SUBJECT]`: the subject is what the map is of (the default one if it
## is left out); `--frames` says which frames `--file` makes, and `--frame` which one the worker makes for the page; which names
## exist is the registry's to say (`subject/subjects`, `map/frames`), so the command checks them, not the parser.  `--frame` is
## marked as allowed in an address (`/map/activities?frame=heat`), so the list of what a page may be given is made from here
## (`web/request.pageOf`).

import std/[options, sequtils, strutils]
import ../../core/[extension, globals]
import ../util/args/args
import ../web/webopts
import ./frames

{.push raises: [].}

type
  Params* = object
    web*: WebMode ## `--file`, `--worker` and the options of serving
    subject*: Option[string] ## none: the default subject
    frames*: seq[string]
      ## what to draw, in the order given; none: the frames that are shown unless told otherwise
    frame*: Option[string]
      ## for the page (with `--worker`): make the data of this one frame, not the page (`?frame=heat`)

  Raw = object ## what the options fill in
    help: bool
    subjects: seq[string]
    frames: seq[string]
    frame: string
    web: WebArgs

func isWord*(value: string): bool =
  ## A name of a subject or a frame: lower case letters and digits.
  value.len > 0 and value.allIt(it in {'a' .. 'z', '0' .. '9'})

func completeFrames(g: Globals, typed: string): seq[string] {.nimcall, raises: [].} =
  ## The names of the frames that start with what is typed (of every subject: the words before it are not known here).
  for f in g.extensions.get(mapFramePoint):
    if f.name.startsWith(typed) and f.name notin result:
      result.add f.name

proc takeFrames(p: var Raw, name: string, values: seq[string]): Problem {.nimcall.} =
  if values.len == 0:
    return refuse("`" & name & "` needs at least one frame")
  for v in values:
    if not isWord(v):
      return refuse("'" & v & "' is not a name of a frame")
  p.frames.add values
  fine

func mapSpec*(): Spec[Raw] =
  ## The options of `nch map`, with the web options.
  Spec[Raw](
    opts:
      @[
        listOption[Raw](
          ["--frames"],
          takeFrames,
          "FRAME...",
          "with `--file`: the frames to make a file of, separated by spaces (see the table below); default: those marked *.  On the page, tick the frames to draw",
          completion = completesFrom(completeFrames),
          valid = isWord,
        ),
        text(
          Raw,
          ["--frame"],
          frame,
          "FRAME",
          "for the page, with `--worker`: make the data of this one frame (the page fetches each frame it shows)",
          address = adValue,
          valid = isWord,
        ),
      ] & webOptions(Raw, web, "the map", "a GeoJSON file for each frame") &
      @[helpFlag(Raw)],
    positional: proc(p: var Raw, arg: string): Problem {.nimcall, raises: [].} =
      if not isWord(arg):
        return refuse("'" & arg & "' is not a name of a subject")
      p.subjects.add arg
      fine,
  )

func finish(raw: Raw): Parsed[Params] =
  let mode = webMode(raw.web)
  if mode.kind == pkProblem:
    return problemWith[Params](mode.problem)
  if raw.subjects.len > 1:
    return problemWith[Params]("expected at most one SUBJECT")
  if raw.frame.len > 0 and mode.params.kind != wkWorker:
    return problemWith[Params]("`--frame` is for the page: it goes with `--worker`")
  if raw.frames.len > 0 and mode.params.kind != wkFile:
    return problemWith[Params](
      "`--frames` chooses the files of `--file`: on the page, tick the frames to draw (the browser remembers them)"
    )
  parsedOk(
    Params(
      web: mode.params,
      subject: (if raw.subjects.len == 1: some(raw.subjects[0])
      else: none(string)),
      frames: raw.frames,
      frame: (if raw.frame.len > 0: some(raw.frame) else: none(string)),
    )
  )

proc parseArgs*(args: seq[string]): Parsed[Params] =
  ## `[SUBJECT] [--frames FRAME...] [--file | --worker | --stop | --port N --start --new-token] [-h]`.
  parseCommand(args, mapSpec(), Raw(web: initWebArgs()), finish)

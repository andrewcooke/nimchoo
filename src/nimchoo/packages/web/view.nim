## What every view (`map`, `plot`) does with its web options, written once (E7 of the fourth review): `--stop` stops the
## server; serving checks that there is something to show and serves the page's address; the worker makes the page, or the
## data of one frame (which the page fetches); `--file` makes the files of the frames.  A view says how to make each.

import std/options
import ../../core/[globals, line]
import ../cache/cache
import ../ui/markup
import ./[launch, pages, webopts]

{.push raises: [].}

type
  Made* = object
    ## What a view made: the files (in the order they are printed) and what is said after them; or the status of a failure
    ## (already reported).
    paths*: seq[string]
    notes*: seq[Line]
    status*: int

  View* = object ## How a view makes what is asked of it.
    command*: string ## "map"
    address*: string ## the page's, without its first slash: "map/activities"
    query*: string ## what the address says besides ("before=2026-11-01"): "" for nothing
    nothing*: proc(): Option[int] {.closure, raises: [].}
      ## before serving or `--file`: some status to stop with (an empty selection, said), or none to go on
    page*: proc(dir: string): Made {.closure, raises: [].}
      ## the worker: make the page in `dir` (the user part of the cache)
    frame*: proc(name, dir: string): Made {.closure, raises: [].}
      ## the worker: make the data of one frame in `dir`, which the page fetches
    files*: proc(dir: string): Made {.closure, raises: [].}
      ## `--file`: make the files of the frames in `dir` (and say what goes with them)
    frameAsked*: Option[string] ## the worker's `--frame`

proc runView*(g: Globals, mode: WebMode, v: View): int =
  ## Do what the web options ask, with the view's ways of making things; the exit status.
  let name = "nch " & v.command
  let dir = cacheDir()
  if dir.isNone:
    return failure(g, name, noCacheDir)
  try:
    makeCacheDirs(dir.get)
  except IOError, OSError:
    return cannotWrite(g, name, dir.get)
  case mode.kind
  of wkStop:
    stopWeb(g, v.command, mode.stopPort, dir.get)
  of wkServe:
    let stop = v.nothing()
    if stop.isSome:
      return stop.get
    serveWeb(
      g,
      v.command,
      WebOptions(port: mode.port, start: mode.start, newToken: mode.newToken),
      dir.get,
      v.address,
      v.query,
    )
  of wkWorker, wkFile:
    if mode.kind == wkFile:
      let stop = v.nothing()
      if stop.isSome:
        return stop.get
    let made =
      if mode.kind == wkFile:
        v.files(userDir(dir.get))
      elif v.frameAsked.isSome:
        v.frame(v.frameAsked.get, userDir(dir.get))
      else:
        v.page(userDir(dir.get))
    if made.status != exitOk:
      return made.status
    for path in made.paths:
      g.show(osOut, ~"<file {path}>")
    if mode.kind == wkFile: # (the worker's output is the paths, which the server reads)
      for note in made.notes:
        g.show(osOut, note)
    exitOk

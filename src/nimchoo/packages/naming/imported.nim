## After an import (`importer/after`): name every activity that has no name yet (`naming.nim`), not only the new ones (an
## `--offline` run leaves some), so the names are decided in the run that imports.  A spinner while it goes on, on a terminal
## (the downloads it makes say their own lines), then one line that says how it went; the activities whose search for a
## place was cut short by bad GPS fixes are warned of in the log.

import std/[options, strformat, strutils]
import ../../core/[errors, extension, logfile]
import ../download/fetch
import ../importer/[after, cmdname, sinks]
import ../names/open
import ../user/session
import ./[namers, naming]

{.push raises: [].}

func summary(c: Named, what: string): string =
  ## "named 3 activities: 2 with a name, 1 with only a start place, 0 with neither; 1 GPS error"
  let gps = c.gpsErrorCount
  let errors =
    if gps > 0:
      "; " & plural(gps, "GPS error", "GPS errors")
    else:
      ""
  let left =
    if c.left > 0:
      "; " & c.leftText
    else:
      ""
  fmt"named {what}: {c.named} with a name, {c.startOnly} with only a start place, {c.nothing} with neither{errors}{left}"

proc nameImported(
    st: Session, ids: seq[int64], ctx: AfterContext
): seq[ImportReport] {.raises: [StoreError, DownloadError].} =
  let todo = pending(st).len
  if todo == 0:
    return
  let names = openNames(ctx.g, st, commandName, ctx.say)
  if names.isNone:
    return
      # (no cache directory to keep the places in: said by the commands that need one)
  let tell = names.get.sink
  let what = insertSep($todo, ',') & (if todo == 1: " activity" else: " activities")
  tell(DownloadEvent(kind: deWorking, label: fmt"naming {what}"))
  var told = false
  defer:
    if not told:
      tell(DownloadEvent(kind: deWorkDone)) # (it failed: the line goes)
  let counts = ensureActivityNames(st, names.get, ctx.g.extensions.get(namerPoint))
  told = true
  tell(DownloadEvent(kind: deWorkDone, message: summary(counts, what)))
  for e in counts.gpsErrors:
    let searches = plural(e.searches, "search", "searches")
    ctx.g.log.log(
      lvWarn,
      commandName,
      leAdvisory,
      fmt"{e.where}  {searches} for a place not made: positions too far apart (GPS errors)",
    )
  ctx.g.log.log(
    lvInfo, commandName, leDone, summary(counts, fmt"{counts.total} activities")
  )

let nameActivities* = AfterImport(
  run: nameImported,
  failed: "the activities could not all be named (the next `nch import` names them)",
) ## after an import: every activity with no name is named

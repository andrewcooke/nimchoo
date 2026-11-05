## `nch sector`: the climbs everyone shares, and their names.  The program names a climb from the places near
## it (see `nch climbs`); here a person may give one a name of their own, or hand it back.  Climbs are shared
## by all users, so the user is not a part of this command.

import ../cli/common
import std/options
import ../climbs/[naming, report]
import ../db/store
import ../errors
import ../names/open
import ../ui/logfile
import ./[edit, params]

{.push raises: [].}

const usage* = """usage: nch sector
       nch sector --edit NAME --rename NEW
       nch sector --edit NAME --auto

Without options, list the climbs (the biggest gain first), as `nch climbs --sectors` does, with "manual"
against the names given by a person.  NAME is a climb's name as listed, "(n/m)" included where several share
a name: "Morro La Cabra (1/3)".

  --edit NAME     change that climb, with one of:
    --rename NEW    give it the name NEW (any words; at most 60 characters; not ending in "(n/m)",
                    which is added by the program when climbs share a name).  The name is kept: the
                    program never changes it.  Several climbs may have the same name.
    --auto          forget the name; it is named again at once from the places near it (or by the next `nch climbs` if the names cannot be had)
  -h, --help      show this help

(The climbs are shared by all users, so `--user` goes nowhere here.)
"""

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch sector ARGS`; returns the exit status.
  let p = parseArgs(args)
  if p.help:
    stdout.say usage
    return exitOk
  if p.problem.len > 0:
    return usageError("nch sector", usage, p.problem)
  if g.user.len > 0:
    return usageError("nch sector", usage, "the climbs are shared by all users: --user has no part in this command")
  var st: Store
  try:
    st = openStore(g)
  except StoreError as e:
    return failure("nch sector", e.msg)
  try:
    if p.list:
      let rows = allSectors(st)
      if rows.len == 0:
        stdout.say "no climbs found yet: `nch climbs` looks for them\n"
      else:
        for l in catalogueLines(rows): stdout.say l & "\n"
      return exitOk
    let id = findShown(st, p.name)
    let was = shownName(st, id)
    if p.auto:
      setAuto(st, id)
      var said = was & ": the name is forgotten"
      let names = openNames(g, st, "sector", proc(line: string) {.closure, raises: [].} = stderr.say line & "\n")
      if names.isSome:
        try:
          discard ensureSectorNames(st, names.get)
          said = was & " is now called " & shownName(st, id)
        except DownloadError as e:
          said.add "; " & e.msg & " (the next `nch climbs` makes one)"
      g.log.log(lvInfo, "sector", leSaved, said)
      stdout.say said & "\n"
    else:
      rename(st, id, p.rename)
      let said = was & " is now called " & shownName(st, id)
      g.log.log(lvInfo, "sector", leSaved, said)
      stdout.say said & "\n"
    exitOk
  except StoreError as e:
    failure("nch sector", e.msg)

## `nch import`: put the activities of FIT files into the database.
## (The command of the activity module; the module is not called `import`
## because that is a Nim keyword.)

import std/[algorithm, os, strutils, tables]
import ../commands/common
import ../db/store
import ../errors
import ../fit/bytes
import ../profile/default
import ../profile/model
import ../warnings
import ./importer

{.push raises: [].}

const usage* = """usage: nch [--db PATH] [--user NAME] import [-q] PATH...

Import the activities in FIT files into the database.  Each PATH is a file, or
a directory that is searched (recursively) for *.fit files.  A file that was
imported before is skipped; a file that cannot be imported is reported and the
others carry on.

  -q, --quiet   report only failures and the summary
  -h, --help    show this help
"""

type
  Found = object
    paths: seq[string]
    problems: seq[string]   ## paths that do not exist, empty directories

func plural(n: int, one, many: string): string =
  $n & " " & (if n == 1: one else: many)

proc isFit(path: string): bool =
  path.splitFile.ext.toLowerAscii == ".fit"

proc collect(args: seq[string]): Found =
  ## The files to import: files as given, FIT files found in directories;
  ## sorted, each once.
  var seen: seq[string]
  for arg in args:
    var here: seq[string]
    try:
      if dirExists(arg):
        for path in walkDirRec(arg):
          if path.isFit: here.add path
        if here.len == 0:
          result.problems.add arg & ": no .fit files found"
      elif fileExists(arg):
        here.add arg
      else:
        result.problems.add arg & ": no such file or directory"
    except OSError as e:
      result.problems.add arg & ": " & e.msg
    for path in here:
      let key = try: absolutePath(path) except OSError, ValueError: path
      if key notin seen:
        seen.add key
        result.paths.add path
  result.paths.sort()

type
  Report* = object
    ## What an import run has to say, kept apart from printing it.
    lines*: seq[string]      ## for stdout
    warnings*: seq[string]   ## for stderr
    imported*, skipped*, failed*: int

proc addWarnings(report: var Report, path: string, ws: seq[Warning]) =
  ## One line per kind of warning in a file: the first of its kind, and how
  ## many more there were.
  var count: Table[WarningKind, int]
  for w in ws: count.mgetOrPut(w.kind, 0) += 1
  var shown: seq[WarningKind]
  for w in ws:
    if w.kind in shown: continue
    shown.add w.kind
    let more = count.getOrDefault(w.kind) - 1
    report.warnings.add "warning: " & path & ": offset " & $w.offset & ": " &
      w.msg & (if more > 0: " (and " & $more & " more like it)" else: "")

proc importPaths*(st: Store, profile: Profile, targets: seq[string],
                  quiet: bool): Report =
  ## Import the files in `targets` (files and directories), one transaction
  ## per file; a file that fails is reported and the others carry on.
  let found = collect(targets)
  for problem in found.problems:
    result.lines.add "failed    " & problem
    inc result.failed
  for path in found.paths:
    var ws: seq[Warning]
    try:
      let r = st.importFile(profile, extractFilename(path), readBytes(path), ws)
      case r.outcome
      of ioImported:
        inc result.imported
        if not quiet:
          result.lines.add "imported  " & path & "  (" &
            plural(r.activities, "activity", "activities") & ", " &
            plural(r.segments, "segment", "segments") & ", " &
            plural(r.coords, "coordinate", "coordinates") & ")"
      of ioAlreadyImported:
        inc result.skipped
        if not quiet:
          result.lines.add "skipped   " & path & "  (already imported)"
    except NchError as e:
      inc result.failed
      result.lines.add "failed    " & path & ": " & e.msg
    except IOError as e:
      inc result.failed
      result.lines.add "failed    " & path & ": " & e.msg
    result.addWarnings(path, ws)
  result.lines.add plural(result.imported + result.skipped + result.failed,
                          "file", "files") & ": " & $result.imported &
    " imported, " & $result.skipped & " skipped, " & $result.failed & " failed"

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch import ARGS`; returns the exit status.
  var quiet = false
  var targets: seq[string]
  for a in args:
    if a in ["-h", "--help"]:
      stdout.say usage
      return exitOk
    elif a in ["-q", "--quiet"]:
      quiet = true
    elif a.startsWith("-") and a != "-":
      return usageError("nch import", usage, "unknown option " & a)
    else:
      targets.add a
  if targets.len == 0:
    return usageError("nch import", usage, "expected at least one PATH")
  var st: Store
  try:
    st = openStore(g)
  except StoreError as e:
    return failure("nch import", e.msg)
  defer: st.close()
  let profile =
    try: loadDefaultProfile()
    except NchError as e:
      return failure("nch import", "cannot load the profile: " & e.msg)
  let report = importPaths(st, profile, targets, quiet)
  for l in report.lines: stdout.say l & "\n"
  for w in report.warnings: stderr.say w & "\n"
  if report.failed > 0: exitFailure else: exitOk

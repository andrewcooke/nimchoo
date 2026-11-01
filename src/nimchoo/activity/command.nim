## `nch import`: put the activities of FIT files into the database.
## (The command of the activity module; the module is not called `import`
## because that is a Nim keyword.)

import std/[algorithm, options, os, strutils, tables, times]
import ../commands/common
import ../db/store
import ../errors
import ../fit/bytes
import ../profile/default
import ../profile/model
import ../warnings
import ./failure
import ./importer
import ./seen

{.push raises: [].}

const usage* = """usage: nch [--db PATH] [--user NAME] import [-q] [--slow] PATH...

Import the activities in FIT files into the database.  Each PATH is a file, or
a directory that is searched (recursively) for *.fit files.  A file whose path,
size and modification time are as when it was last looked at is skipped
without being read (this includes files that could not be imported); a file
that cannot be imported is reported and the others carry on.

  -q, --quiet   report only failures and the summary
  --slow        read and check every file, even those unchanged since last
                time (finds files that were moved or copied; retries failures)
  -h, --help    show this help
"""

type
  ImportOptions* = object
    quiet*, slow*: bool
    profile*: ProfileSource   ## nil: the embedded profile

  Candidate = object
    path: string      ## as found, for display
    key: string       ## absolute and normalised: what is remembered
    size, mtime: int64

  Found = object
    files: seq[Candidate]
    problems: seq[string]   ## paths that do not exist, empty directories

  Report* = object
    ## What an import run has to say, kept apart from printing it.
    lines*: seq[string]      ## for stdout
    warnings*: seq[string]   ## for stderr
    imported*, skipped*, failed*, known*: int

func plural(n: int, one, many: string): string =
  $n & " " & (if n == 1: one else: many)

proc isFit(path: string): bool =
  path.splitFile.ext.toLowerAscii == ".fit"

proc embeddedProfile(): Profile {.raises: [].} =
  try: loadDefaultProfile()
  except NchError as e:
    raiseAssert "the embedded profile does not load: " & e.msg   # a bug

proc candidate(path: string): Candidate {.raises: [OSError].} =
  ## The file at `path`, statted.
  let info = getFileInfo(path)
  let key = try: normalizedPath(absolutePath(path)) except ValueError: path
  Candidate(path: path, key: key, size: int64(info.size),
            mtime: info.lastWriteTime.toUnix)

proc collect(args: seq[string]): Found =
  ## The files to import: files as given, FIT files found in directories;
  ## each once, sorted by path.
  var known: seq[string]
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
      try:
        let c = candidate(path)
        if c.key notin known:
          known.add c.key
          result.files.add c
      except OSError as e:
        result.problems.add path & ": " & e.msg
  result.files.sort do (a, b: Candidate) -> int: cmp(a.path, b.path)

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

proc importPaths*(st: Store, targets: seq[string],
                  opts: ImportOptions = ImportOptions()): Report =
  ## Import the files in `targets` (files and directories), one transaction
  ## per file; a file that fails is reported and the others carry on.  Files
  ## unchanged since they were last looked at are skipped unread unless
  ## `opts.slow`.
  let found = collect(targets)
  for problem in found.problems:
    result.lines.add "failed    " & problem
    inc result.failed
  var table: SeenTable
  if not opts.slow:
    try:
      table = loadSeen(st)
    except StoreError as e:
      result.warnings.add "warning: cannot read what was seen before, " &
        "checking every file: " & e.msg
  var pending: SeenBuffer
  var cached: Option[Profile]
  let profile: ProfileSource = proc(): Profile {.closure, raises: [].} =
    if cached.isNone:
      cached = some(if opts.profile.isNil: embeddedProfile() else: opts.profile())
    cached.get

  template flushSeen() =
    try:
      st.flush(pending)
    except StoreError as e:
      pending = SeenBuffer()
      result.warnings.add "warning: cannot record the files seen: " & e.msg

  for c in found.files:
    let before = table.getOrDefault(c.key)
    if c.key in table and before.matches(c.size, c.mtime):
      if before.failed:
        inc result.known
        if not opts.quiet:
          result.lines.add "known     " & c.path & "  (failed before: " &
            before.message & ")"
      else:
        inc result.skipped
        if not opts.quiet:
          result.lines.add "skipped   " & c.path & "  (unchanged)"
      continue
    var ws: seq[Warning]
    var row = Seen(size: c.size, mtime: c.mtime)
    try:
      let r = st.importFileWith(profile, extractFilename(c.path),
                                readBytes(c.path), ws)
      row.fileId = r.fileId
      case r.outcome
      of ioImported:
        inc result.imported
        if not opts.quiet:
          result.lines.add "imported  " & c.path & "  (" &
            plural(r.activities, "activity", "activities") & ", " &
            plural(r.segments, "segment", "segments") & ", " &
            plural(r.coords, "coordinate", "coordinates") & ")"
      of ioAlreadyImported:
        inc result.skipped
        if not opts.quiet:
          result.lines.add "skipped   " & c.path & "  (already imported)"
    except NchError as e:
      inc result.failed
      result.lines.add "failed    " & c.path & ": " & e.msg
      row.failure = $failureOf(e)
      row.message = e.msg
    except IOError as e:
      inc result.failed
      result.lines.add "failed    " & c.path & ": " & e.msg
      row.failure = $fkUnreadable
      row.message = e.msg
    pending.add c.key, row
    if pending.full: flushSeen()
    result.addWarnings(c.path, ws)
  flushSeen()
  var summary = plural(result.imported + result.skipped + result.failed +
                       result.known, "file", "files") & ": " &
    $result.imported & " imported, " & $result.skipped & " skipped, " &
    $result.failed & " failed"
  if result.known > 0:
    summary.add ", " & plural(result.known, "known failure", "known failures") &
      " (use --slow to retry)"
  result.lines.add summary

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch import ARGS`; returns the exit status.
  var opts = ImportOptions()
  var targets: seq[string]
  for a in args:
    if a in ["-h", "--help"]:
      stdout.say usage
      return exitOk
    elif a in ["-q", "--quiet"]:
      opts.quiet = true
    elif a == "--slow":
      opts.slow = true
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
  let report = importPaths(st, targets, opts)
  for l in report.lines: stdout.say l & "\n"
  for w in report.warnings: stderr.say w & "\n"
  if report.failed > 0: exitFailure else: exitOk

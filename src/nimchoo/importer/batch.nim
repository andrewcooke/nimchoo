## Importing a batch of paths: find the files, skip those that have not
## changed, import the rest, one transaction per file.  Everything that
## happens is announced as an event (events.nim); nothing is printed here.

import std/[algorithm, options, os, strutils, tables, times]
import ../db/[channel, store]
import ../errors
import ../fit/bytes
import ../profile/default
import ../profile/model
import ../profiling
import ../warnings
import ./events
import ./failure
import ./importer
import ./seen
import ./sinks

{.push raises: [].}

type
  ImportOptions* = object
    quiet*, slow*: bool
    profile*: ProfileSource   ## nil: the embedded profile
    steps*: seq[ImportStep]   ## what modules add to an import (heart rate, ...)

  Candidate = object
    path: string      ## as found, for display
    key: string       ## absolute and normalised: what is remembered
    size, mtime: int64

  Problem = object
    path, message: string

  Found = object
    files: seq[Candidate]
    problems: seq[Problem]   ## paths that do not exist, empty directories

proc isFit(path: string): bool =
  path.splitFile.ext.toLowerAscii == ".fit"

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
          result.problems.add Problem(path: arg, message: "no .fit files found")
      elif fileExists(arg):
        here.add arg
      else:
        result.problems.add Problem(path: arg,
                                    message: "no such file or directory")
    except OSError as e:
      result.problems.add Problem(path: arg, message: e.msg)
    for path in here:
      try:
        let c = candidate(path)
        if c.key notin known:
          known.add c.key
          result.files.add c
      except OSError as e:
        result.problems.add Problem(path: path, message: e.msg)
  result.files.sort do (a, b: Candidate) -> int: cmp(a.path, b.path)

proc importPaths*(st: Store, targets: seq[string], opts: ImportOptions,
                  emit: Sink): Summary =
  ## Import the files in `targets` (files and directories), one transaction
  ## per file; a file that fails is reported and the others carry on.  Files
  ## unchanged since they were last looked at are skipped unread unless
  ## `opts.slow`.  Every step is announced to `emit`; the totals are returned.
  startClock()
  var found: Found
  timed "find files":
    found = collect(targets)
  result.total = found.problems.len + found.files.len
  emit ImportEvent(kind: evStart, total: result.total)
  var index = 0
  template finished(e: ImportEvent) =
    let ev = e
    result.tally(ev)
    emit ev

  for p in found.problems:
    inc index
    finished ImportEvent(kind: evFileDone, index: index, path: p.path,
                         outcome: oFailed, failure: fkNotFound,
                         message: p.message)
  var table: SeenTable
  if not opts.slow:
    try:
      table = loadSeen(st)
    except StoreError as e:
      result.notes.add "cannot read what was seen before, checking every " &
        "file: " & e.msg
  var pending: SeenBuffer
  var importedFrom: Table[int64, string]   ## file id -> path, for files imported in this run
  var cached: Option[Profile]
  var profileNote = ""                 # said at the end if the author's profile is in use (or unusable)
  let profile: ProfileSource = proc(): Profile {.closure, raises: [].} =
    if cached.isNone:
      if opts.profile.isNil:
        let d = defaultProfile()
        profileNote = d.note
        cached = some(d.profile)
      else:
        cached = some(opts.profile())
    cached.get

  template flushSeen() =
    try:
      st.flush(pending)
    except StoreError as e:
      pending = SeenBuffer()
      result.notes.add "cannot record the files seen: " & e.msg

  for c in found.files:
    inc index
    emit ImportEvent(kind: evFileStart, startIndex: index, startPath: c.path)
    let before = table.getOrDefault(c.key)
    if c.key in table and before.matches(c.size, c.mtime):
      if before.failed:
        finished ImportEvent(kind: evFileDone, index: index, path: c.path,
                             outcome: oKnownFailure,
                             failure: kindOf(before.failure),
                             message: before.message)
      else:
        finished ImportEvent(kind: evFileDone, index: index, path: c.path,
                             outcome: oUnchanged)
      continue
    var ws: seq[Warning]
    var row = Seen(size: c.size, mtime: c.mtime)
    var ev = ImportEvent(kind: evFileDone, index: index, path: c.path)
    try:
      var bytes: seq[byte]
      timed "read file":
        bytes = readBytes(c.path)
      let r = st.importFileWith(profile, extractFilename(c.path), bytes, ws, opts.steps)
      row.fileId = r.fileId
      case r.outcome
      of ioImported:
        ev.outcome = oImported
        ev.counts = Counts(activities: r.activities, segments: r.segments,
                           coords: r.coords, extras: r.extras)
        importedFrom[r.fileId] = c.path
      of ioDuplicate:
        ev.outcome = oDuplicate
        ev.sameAs = importedFrom.getOrDefault(r.fileId)
        if ev.sameAs.len == 0: ev.sameAs = pathOfFile(st, r.fileId)
    except NchError as e:
      ev.outcome = oFailed
      ev.failure = failureOf(e)
      ev.message = e.msg
    except IOError as e:
      ev.outcome = oFailed
      ev.failure = fkUnreadable
      ev.message = e.msg
    if ev.outcome == oFailed:
      row.failure = $ev.failure
      row.message = ev.message
    ev.advisories = ws
    pending.add c.key, row
    if pending.full: flushSeen()
    finished ev
  timed "flush seen":
    flushSeen()
  if enabled:
    try: stderr.write report()
    except IOError: discard
  if profileNote.len > 0: result.notes.add profileNote
  emit ImportEvent(kind: evFinish, summary: result)

proc importReport*(st: Store, targets: seq[string],
                   opts: ImportOptions = ImportOptions()): Report =
  ## `importPaths`, with the plain output collected in a Report.
  result = Report()
  discard importPaths(st, targets, opts, reportSink(result, opts.quiet))

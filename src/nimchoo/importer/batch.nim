## Importing a batch of paths: find the files, skip those that have not
## changed, import the rest, one transaction per file.  Everything that
## happens is announced as an event (events.nim); nothing is printed here.

import std/[algorithm, monotimes, options, os, sets, strutils, tables, times]
import ../db/[channel, checkpointer, store]
import ../core/errors
import ../core/ids
import ../profile/default
import ../profile/model
import ../profiling
import ../warnings
import ./events
import ./failure
import ./importer
import ./pool
import ./work
import ./seen

{.push raises: [].}

type
  ImportOptions* = object
    quiet*, slow*: bool
    jobs*: int
      ## threads that prepare the files (decode them); 1 or less: none, in this thread
    profile*: ProfileSource ## nil: the embedded profile
    steps*: seq[ImportStep] ## what modules add to an import (heart rate, ...)

  Candidate = object
    path: string ## as found, for display
    key: string ## absolute and normalised: what is remembered
    size, mtime: int64

  Problem = object
    path, message: string

  Found = object
    files: seq[Candidate]
    problems: seq[Problem] ## paths that do not exist, empty directories

proc isFit(path: string): bool =
  path.splitFile.ext.toLowerAscii == ".fit"

proc candidate(path: string): Candidate {.raises: [OSError].} =
  ## The file at `path`, statted.
  let info = getFileInfo(path)
  let key =
    try:
      normalizedPath(absolutePath(path))
    except ValueError:
      path
  Candidate(
    path: path, key: key, size: int64(info.size), mtime: info.lastWriteTime.toUnix
  )

proc collect(args: seq[string]): Found =
  ## The files to import: files as given, FIT files found in directories;
  ## each once, sorted by path.
  var known: seq[string]
  for arg in args:
    var here: seq[string]
    try:
      if dirExists(arg):
        for path in walkDirRec(arg):
          if path.isFit:
            here.add path
        if here.len == 0:
          result.problems.add Problem(path: arg, message: "no .fit files found")
      elif fileExists(arg):
        here.add arg
      else:
        result.problems.add Problem(path: arg, message: "no such file or directory")
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
  result.files.sort do(a, b: Candidate) -> int:
    cmp(a.path, b.path)

proc importPaths*(
    st: Store, targets: seq[string], opts: ImportOptions, emit: Sink
): Summary =
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
    finished ImportEvent(
      kind: evFileDone,
      index: index,
      path: p.path,
      outcome: oFailed,
      failure: fkNotFound,
      message: p.message,
    )
  var table: SeenTable
  if not opts.slow:
    try:
      table = loadSeen(st)
    except StoreError as e:
      result.notes.add "cannot read what was seen before, checking every " & "file: " &
        e.msg
  var pending: SeenBuffer
  var importedFrom: Table[ids.FileId, string]
    ## file id -> path, for files imported in this run
  template flushSeen() =
    try:
      st.flush(pending)
    except StoreError as e:
      pending = SeenBuffer()
      result.notes.add "cannot record the files seen: " & e.msg

  # the files that need work; the others are announced as they come
  var work: seq[int] # their places among the files
  for k, c in found.files:
    if not (c.key in table and table.getOrDefault(c.key).matches(c.size, c.mtime)):
      work.add k

  var cached: Option[Profile]
  var profileBytes = ""
  var profileNote = "" # said at the end if the author's profile is in use (or unusable)
  let profile: ProfileSource = proc(): Profile {.closure, raises: [].} =
    if cached.isNone:
      if opts.profile.isNil:
        let d = defaultProfile()
        profileNote = d.note
        profileBytes = d.bytes
        cached = some(d.profile)
      else:
        cached = some(opts.profile())
    cached.get
  let channels = channelsOf(opts.steps)
  # here, the database says whether a content is in it already (so also what was written earlier in
  # this run); the workers have a list made when they start
  let askDatabase: KnownCheck = proc(digest: string): bool {.closure, raises: [].} =
    try:
      knownFile(st, digest).isSome
    except StoreError:
      false
  var pool: Pool
  var pooled = false
  if work.len > 1 and opts.jobs > 1 and opts.profile.isNil:
    var known: HashSet[string]
    try:
      known = knownDigests(st)
    except StoreError as e:
      result.notes.add "cannot read which files are in the database, checking each one: " &
        e.msg
    discard profile() # (the workers load their own copy of this spreadsheet)
    pool = startPool(
      min(opts.jobs, work.len),
      Config(profileBytes: profileBytes, channels: channels, known: known),
    )
    pooled = pool.started > 0
  # How much is with the workers (or finished and waiting for its turn): at most `maxFiles` files
  # and `maxBytes` of FIT files (the decoded files take two or three times that in memory).  A wide
  # window means less waiting for a slow file at the front; counting bytes lets any number of tiny
  # files (monitoring data is mostly that) queue up behind a big one.
  const
    maxFiles = 256
    maxBytes = 48 * 1024 * 1024
  var submitted = 0 # how many of `work` the workers have been given
  var consumed = 0 # how many have been taken back
  var inFlight = 0'i64 # bytes of the files with the workers
  var early: Table[int, Prepared] # results that came before their turn
  template feed() =
    while pooled and submitted < work.len and submitted - consumed < maxFiles and (
      submitted == consumed or inFlight + found.files[work[submitted]].size <= maxBytes
    )
    :
      pool.submit Job(index: work[submitted], path: found.files[work[submitted]].path)
      inFlight += found.files[work[submitted]].size
      inc submitted

  # the log is copied back into the database by a thread of its own, not by the writer, which would stop
  # for it (the pause is a third of a second or more, several times in a long import)
  var checkpoints: Checkpointer
  if work.len > 0:
    checkpoints = startCheckpointer(st.path)
    if checkpoints.running:
      try:
        st.setAutoCheckpoint(0)
      except StoreError:
        discard
  feed()

  for k, c in found.files:
    inc index
    emit ImportEvent(kind: evFileStart, startIndex: index, startPath: c.path)
    let before = table.getOrDefault(c.key)
    if c.key in table and before.matches(c.size, c.mtime):
      if before.failed and kindOf(before.failure) == fkMonitor:
        finished ImportEvent(
          kind: evFileDone,
          index: index,
          path: c.path,
          outcome: oMonitor,
          failure: fkMonitor,
        )
      elif before.failed:
        finished ImportEvent(
          kind: evFileDone,
          index: index,
          path: c.path,
          outcome: oKnownFailure,
          failure: kindOf(before.failure),
          message: before.message,
        )
      else:
        finished ImportEvent(
          kind: evFileDone, index: index, path: c.path, outcome: oUnchanged
        )
      continue
    # the file's turn: its result, from a worker or made here
    var prep: Prepared
    if pooled:
      if k notin early:
        # waiting: is it the order (other results are here) or are the workers still busy (none is)?
        timed (if early.len > 0: "wait: order" else: "wait: workers busy"):
          while k notin early:
            let r = pool.receive()
            early[r.index] = r
      discard early.pop(k, prep)
      inc consumed
      inFlight -= c.size
      feed()
    else:
      prep = prepareFile(profile, channels, askDatabase, Job(index: k, path: c.path))
    var row = Seen(size: c.size, mtime: c.mtime)
    var ev = ImportEvent(kind: evFileDone, index: index, path: c.path)
    let t0 = getMonoTime()
    case prep.outcome
    of poFailed:
      ev.outcome = if prep.failure == fkMonitor: oMonitor else: oFailed
      ev.failure = prep.failure
      ev.message = prep.message
    of poKnown, poDecoded:
      try:
        # (the database has the last word: it also knows what was written earlier in this run)
        let have = knownFile(st, prep.digest)
        if have.isSome:
          row.fileId = have.get
          ev.outcome = oDuplicate
          ev.sameAs = importedFrom.getOrDefault(have.get)
          if ev.sameAs.len == 0:
            ev.sameAs = pathOfFile(st, have.get)
        elif prep.outcome == poKnown:
          ev.outcome = oFailed
          ev.failure = fkStore
          ev.message =
            "the file's contents were in the database when the import began and are not now"
        else:
          let r = st.writeDecoded(
            extractFilename(c.path), prep.digest, prep.decoded, opts.steps
          )
          row.fileId = r.fileId
          ev.outcome = oImported
          ev.counts = Counts(
            activities: r.activities,
            segments: r.segments,
            coords: r.coords,
            extras: r.extras,
          )
          importedFrom[r.fileId] = c.path
      except StoreError as e:
        ev.outcome = oFailed
        ev.failure = fkStore
        ev.message = e.msg
    if ev.outcome != oFailed:
      fileDone(
        prep.bytes,
        prep.nanos + (getMonoTime() - t0).inNanoseconds,
        ev.outcome == oImported,
      )
    if ev.outcome in {oFailed, oMonitor}:
      row.failure = $ev.failure
      row.message = ev.message
    if ev.outcome != oDuplicate:
      # (a file whose content is in already has nothing to say)
      ev.advisories = prep.warnings
    pending.add c.key, row
    if pending.full:
      flushSeen()
    finished ev
  if pooled:
    pool.finish()
  if checkpoints.running:
    checkpoints.stop()
    try:
      st.setAutoCheckpoint(20000)
    except StoreError:
      discard
  timed "flush seen":
    flushSeen()
  if enabled:
    try:
      stderr.write report()
    except IOError:
      discard
  if profileNote.len > 0:
    result.notes.add profileNote
  emit ImportEvent(kind: evFinish, summary: result)

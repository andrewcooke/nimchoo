## Threads that prepare files (work.nim) while the main thread writes the database.  The workers
## never touch the database: they take jobs from one channel and send each result back on another.
## The main thread asks for results in the order it needs them (see batch.nim), so what is written
## and announced is the same as if there were no threads.
##
## What the workers read (`config`) is set before they start and not changed until they have
## finished.  Each loads its own copy of the profile, so no object is shared between threads.

import std/[options, sets, typedthreads]
import ../core/errors
import ../profile/load
import ../packages/util/profiling/profiling
import ./failure
import ./importer
import ./work

{.push raises: [].}

type
  Config* = object
    profileBytes*: string ## the spreadsheet; each worker loads it
    channels*: seq[string] ## the record fields the import steps want
    known*: HashSet[string] ## hashes of the contents already in the database

  Message = object
    finished: bool ## a worker is ending: `phases` are its timers
    prepared: Prepared
    phases: seq[PhaseTotal]

  Pool* = object
    threads: seq[Thread[int]] ## (made once; they must not move)
    started*: int ## how many of them could be started

var
  config: Config
  jobs: Channel[Job]
  results: Channel[Message]
  channelsOpen = false
    ## (the built-in channels are opened once and never closed: after `close`
    ## they keep a pointer to freed memory, so opening them again frees it twice)

proc worker(id: int) {.thread.} =
  {.cast(gcsafe).}:
    let isKnown: KnownCheck = proc(digest: string): bool {.closure, raises: [].} =
      digest in config.known
    var profile: Option[Profile] # (loaded when a file first needs it)
    var problem = ""
    let source: ProfileSource = proc(): Profile {.closure, raises: [].} =
      if profile.isNone:
        try:
          profile = some(loadProfileFromBytes(config.profileBytes))
        except NchError as e:
          problem = e.msg
          profile = some(Profile()) # (every file is then reported: see below)
      profile.get
    while true:
      let job = jobs.recv()
      if job.index < 0:
        break
      var m = Message()
      m.prepared = prepareFile(source, config.channels, isKnown, job)
      if problem.len > 0 and m.prepared.outcome == poDecoded:
        m.prepared = Prepared(
          index: job.index,
          outcome: poFailed,
          failure: fkBadFormat,
          message: "cannot load the profile: " & problem,
        )
      results.send m
    results.send Message(finished: true, phases: takePhases())

proc startPool*(n: int, cfg: Config): Pool =
  ## Start up to `n` workers (`started` says how many there are; none means do the work yourself).
  {.cast(gcsafe).}:
    config = cfg
  if not channelsOpen:
    jobs.open()
    results.open()
    channelsOpen = true
  result.threads = newSeq[Thread[int]](n)
  for i in 0 ..< n:
    try:
      createThread(result.threads[i], worker, i)
      inc result.started
    except ResourceExhaustedError:
      break # (the system will not give more: the ones that started do the work)

proc submit*(p: Pool, job: Job) =
  ## Give a worker a file to prepare.
  jobs.send job

proc receive*(p: Pool): Prepared =
  ## The next result, from whichever worker finishes first (block until there is one).
  while true:
    let m = results.recv()
    if not m.finished:
      return m.prepared

proc finish*(p: var Pool) =
  ## Stop the workers, add their timers to this thread's, and wait for them to end.  (Results that
  ## nobody asked for are thrown away.)
  for _ in 0 ..< p.started:
    jobs.send Job(index: -1)
  var ended = 0
  while ended < p.started:
    let m = results.recv()
    if m.finished:
      inc ended
      mergePhases(m.phases)
  if p.started > 0:
    joinThreads(p.threads.toOpenArray(0, p.started - 1))

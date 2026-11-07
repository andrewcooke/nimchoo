## Timers for finding out where a long job (an import of thousands of files) spends its time.
## Off unless the environment has NCH_PROFILE: then each `timed("phase"): ...` adds its time to the
## phase, and `report` says the totals.  Costs a check of one flag when off.

import std/[algorithm, monotimes, os, strutils, tables, times]

{.push raises: [].}

type Phase = object
  nanos: int64
  longest: int64 ## the slowest single call
  calls: int

type FileTime = tuple[bytes: int, nanos: int64, imported: bool]

var phases {.threadvar.}: OrderedTable[string, Phase]
  # (each thread has its own: see `takePhases`)
var files: seq[FileTime]
var merged = false
  ## whether tables of other threads were added (then the times add up to more than the clock)
var started: MonoTime

let enabled* = existsEnv("NCH_PROFILE") ## whether the timers are on

proc add(name: string, nanos: int64) =
  var p = phases.getOrDefault(name)
  p.nanos += nanos
  p.longest = max(p.longest, nanos)
  inc p.calls
  phases[name] = p

type PhaseTotal* = tuple[name: string, nanos: int64, calls: int, longest: int64]

proc takePhases*(): seq[PhaseTotal] =
  ## The totals of this thread, which are then forgotten here (a worker sends them to the thread
  ## that reports, before it ends).
  if not enabled:
    return
  for k, v in phases:
    result.add (k, v.nanos, v.calls, v.longest)
  phases.clear()

proc mergePhases*(totals: seq[PhaseTotal]) =
  ## Add the totals of another thread to this thread's.
  if totals.len > 0:
    merged = true
  for t in totals:
    var p = phases.getOrDefault(t.name)
    p.nanos += t.nanos
    p.calls += t.calls
    p.longest = max(p.longest, t.longest)
    phases[t.name] = p

template timed*(name: string, body: untyped) =
  ## Run `body`, and if profiling is on add the time it took to the phase `name`.
  if enabled:
    let t0 = getMonoTime()
    try:
      body
    finally:
      add(name, (getMonoTime() - t0).inNanoseconds)
  else:
    body

proc fileDone*(bytes: int, nanos: int64, imported: bool) =
  ## One file looked at: its size, how long it took altogether, whether it gave activities.
  if enabled:
    {.cast(gcsafe).}:
      files.add (bytes, nanos, imported) # (only the thread that reports calls this)

proc startClock*() =
  if enabled:
    started = getMonoTime()

proc report*(): string =
  ## A table of the phases: milliseconds, share of the time since `startClock`, and calls.
  if not enabled:
    return
  let total = max(1'i64, (getMonoTime() - started).inNanoseconds)
  var rows: seq[(string, Phase)]
  for k, v in phases:
    rows.add (k, v)
  rows.sort do(a, b: (string, Phase)) -> int:
    cmp(b[1].nanos, a[1].nanos)
  result = "phase                      ms      %   calls   us/call   longest ms\n"
  for (k, v) in rows:
    result.add k.alignLeft(22) & align($(v.nanos div 1_000_000), 8) &
      align($(v.nanos * 100 div total), 7) & align($v.calls, 8) &
      align($(v.nanos div 1000 div max(1, v.calls)), 10) &
      align($(v.longest div 1_000_000), 13) & "\n"
  result.add "total".alignLeft(22) & align($(total div 1_000_000), 8) & "\n"
  if merged:
    result.add "(the times of the threads are added up: they can come to more than the total)\n"
  # by the size of the file
  const limits = [
    (10_000, "under 10 KB"),
    (50_000, "10 - 50 KB"),
    (200_000, "50 - 200 KB"),
    (high(int), "over 200 KB"),
  ]
  result.add "\nfiles by size       files   imported        MB      ms   ms/file    ms/MB\n"
  var lower = 0
  for (upper, label) in limits:
    var n, imported = 0
    var bytes = 0
    var nanos = 0'i64
    {.cast(gcsafe).}:
      for f in files:
        if f.bytes >= lower and f.bytes < upper:
          inc n
          if f.imported:
            inc imported
          bytes += f.bytes
          nanos += f.nanos
    lower = upper
    if n == 0:
      continue
    let ms = nanos div 1_000_000
    let mb = bytes.float / 1e6
    result.add label.alignLeft(18) & align($n, 8) & align($imported, 11) &
      align(mb.formatFloat(ffDecimal, 1), 10) & align($ms, 8) & align($(ms div n), 10) &
      align((if mb > 0: $int(ms.float / mb) else: "-"), 9) & "\n"

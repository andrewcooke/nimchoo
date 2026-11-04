## Timers for finding out where a long job (an import of thousands of files) spends its time.
## Off unless the environment has NCH_PROFILE: then each `timed("phase"): ...` adds its time to the
## phase, and `report` says the totals.  Costs a check of one flag when off.

import std/[algorithm, monotimes, os, strutils, tables, times]

{.push raises: [].}

type Phase = object
  nanos: int64
  calls: int

var phases: OrderedTable[string, Phase]
var started: MonoTime

let enabled* = existsEnv("NCH_PROFILE")
  ## whether the timers are on

proc add(name: string, nanos: int64) {.gcsafe.} =
  {.cast(gcsafe).}:
    var p = phases.getOrDefault(name)
    p.nanos += nanos
    inc p.calls
    phases[name] = p

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

proc startClock*() =
  if enabled: started = getMonoTime()

proc report*(): string =
  ## A table of the phases: milliseconds, share of the time since `startClock`, and calls.
  if not enabled: return
  let total = max(1'i64, (getMonoTime() - started).inNanoseconds)
  var rows: seq[(string, Phase)]
  {.cast(gcsafe).}:
    for k, v in phases: rows.add (k, v)
  rows.sort do (a, b: (string, Phase)) -> int: cmp(b[1].nanos, a[1].nanos)
  result = "phase                      ms      %   calls\n"
  for (k, v) in rows:
    result.add k.alignLeft(22) & align($(v.nanos div 1_000_000), 8) &
      align($(v.nanos * 100 div total), 7) & align($v.calls, 8) & "\n"
  result.add "total".alignLeft(22) & align($(total div 1_000_000), 8) & "\n"

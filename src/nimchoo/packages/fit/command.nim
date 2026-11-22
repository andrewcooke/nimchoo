## `nch fit`: read a FIT file and dump it as text or as SDK-format CSV.

import std/[options, strutils, times]
import ../util/bytes/bytes
import ./time
import ../../core/globals
import ../util/args/[args, usage]
import ./params
import ./csvout
import ./reader
import ./records
import ./default
import ./load
import ../../core/errors
import ./model
import ../util/warnings/warnings

{.push raises: [].}

const
  synopsis = "usage: nch fit [--csv] [--profile PATH] FILE"
  intro = @[~"Read a FIT file and print its messages."]

proc options*(g: Globals): seq[OptDoc] {.nimcall, raises: [].} =
  ## The options of `nch fit`, described (for tab completion).
  fitSpec().docs

proc usageText*(width: int): seq[Line] =
  ## The usage: the synopsis, the introduction and the options, wrapped to `width`.
  usageOf(synopsis, width, intro, fitSpec().docs)

const isoFormat = "yyyy-MM-dd'T'HH:mm:ss"

proc fitText(v: int64, zulu: bool): string =
  ## A FIT time as text; a number that cannot be a time (the field may be declared wider than 32 bits) as the number.
  if not isFitTime(FitTime(v)):
    return $v
  fitToTime(FitTime(v)).utc.format(isoFormat) & (if zulu: "Z" else: "")

proc textValue(p: Profile, r: Record, f: FieldValue): string =
  case f.kind
  of vkInt:
    for i, v in f.ints:
      if i > 0:
        result.add '|'
      case f.typeName
      of "date_time":
        result.add fitText(v, true)
      of "local_date_time":
        result.add fitText(v, false)
      of "timestamp_16":
        if r.timestamp.isSome: # the record's expanded time, not the raw bits
          result.add fitText(int64(r.timestamp.get), true)
        else:
          result.add $v
      else:
        result.add valueName(p, f, i)
  of vkFloat, vkString:
    result = fmtValue(f)

proc textLine*(p: Profile, r: Record): string =
  ## `name: field=value units  field=value units ...`
  result = (if r.name.len == 0: "unknown(" & $r.number & ")" else: r.name) & ":"
  for i, f in r.fields:
    result.add(if i == 0: " " else: "  ")
    let name =
      if f.name.len == 0:
        "?" & $f.number
      elif f.dev:
        "dev." & f.name
      else:
        f.name
    result.add name & "=" & textValue(p, r, f)
    if f.units.len > 0 and
        f.typeName notin ["date_time", "local_date_time", "timestamp_16"]:
      result.add " " & f.units

proc renderInto*(
    p: Profile,
    data: seq[byte],
    csv: bool,
    lines: var seq[string],
    warnings: var seq[Warning],
) {.raises: [FitError].} =
  ## Append the lines for `data` to `lines` and any warnings to `warnings`.
  ## If reading fails part way, what was read before the error is kept.
  var r = initReader(p, data)
  try:
    for ev in r.events(p):
      if csv:
        lines.add csvLine(ev)
      elif ev.kind == evRecord:
        lines.add textLine(p, ev.record)
  finally:
    warnings.add r.warnings

func about(path, msg: string): string =
  ## A message about the file at `path`, which names it (unless it already does).
  if path in msg:
    msg
  else:
    path & ": " & msg

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch fit ARGS`; returns the exit status.  (It does not use
  ## the database, so ignores the global options.)
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    g.showAll osOut, usageText(g.textWidth(osOut))
    return exitOk
  of pkProblem:
    return usageError(g, "nch fit", usageText(g.textWidth(osErr)), parsed.why)
  of pkUnit:
    return unitRetry(g, "nch fit", parsed.fix, run)
  of pkOk:
    discard
  let (csv, file) = (parsed.params.csv, parsed.params.file)
  var
    lines: seq[string]
    warnings: seq[Warning]
    problem = ""
  try:
    let p =
      try:
        if parsed.params.profile.isSome:
          loadProfile(parsed.params.profile.get)
        else:
          let d = defaultProfile()
          if d.problem.len > 0:
            g.warn d.problem
          d.profile
      except NchError, IOError:
        return
          failure(g, "nch fit", ~"cannot use the profile: {getCurrentExceptionMsg()}")
    try:
      renderInto(p, readBytes(file), csv, lines, warnings)
    except FitError as e:
      problem = about(file, e.msg) # report it after the output so far
  except NchError as e:
    return failure(g, "nch fit", e.msg)
  except IOError as e:
    return failure(g, "nch fit", about(file, e.msg))
  except OSError as e:
    return failure(g, "nch fit", about(file, e.msg))
  try:
    for l in lines:
      stdout.write g.inTheme(osOut, l) & "\n"
  except IOError as e:
    return failure(g, "nch fit", ~"cannot write the output: {e.msg}")
  for w in warnings:
    g.warn ~"offset {w.offset}: {w.msg}"
  if problem.len > 0:
    failure(g, "nch fit", problem)
  else:
    exitOk

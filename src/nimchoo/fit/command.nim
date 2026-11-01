## `nch fit`: read a FIT file and dump it as text or as SDK-format CSV.

import std/[options, strutils, times]
import ./bytes
import ./time
import ../cli/common
import ./csvout
import ./reader
import ./records
import ../profile/default
import ../errors
import ../profile/model
import ../warnings

{.push raises: [].}

const usage* = """usage: nch fit [--csv] [--profile PATH] FILE

Read a FIT file and print its messages.

  --csv           SDK-format CSV (including definitions) instead of text
  --profile PATH  use this Profile.xlsx instead of the built-in one
  -h, --help      show this help
"""

const isoFormat = "yyyy-MM-dd'T'HH:mm:ss"

proc textValue(p: Profile, r: Record, f: FieldValue): string =
  case f.kind
  of vkInt:
    for i, v in f.ints:
      if i > 0: result.add '|'
      case f.typeName
      of "date_time": result.add fitToTime(v).utc.format(isoFormat) & "Z"
      of "local_date_time": result.add fitToTime(v).utc.format(isoFormat)
      of "timestamp_16":
        if r.timestamp.isSome:  # the record's expanded time, not the raw bits
          result.add fitToTime(r.timestamp.get).utc.format(isoFormat) & "Z"
        else: result.add $v
      else: result.add valueName(p, f, i)
  of vkFloat, vkString:
    result = fmtValue(f)

proc textLine*(p: Profile, r: Record): string =
  ## `name: field=value units  field=value units ...`
  result = (if r.name.len == 0: "unknown(" & $r.number & ")" else: r.name) & ":"
  for i, f in r.fields:
    result.add(if i == 0: " " else: "  ")
    let name =
      if f.name.len == 0: "?" & $f.number
      elif f.dev: "dev." & f.name
      else: f.name
    result.add name & "=" & textValue(p, r, f)
    if f.units.len > 0 and f.typeName notin ["date_time", "local_date_time", "timestamp_16"]:
      result.add " " & f.units

proc renderInto*(p: Profile, data: seq[byte], csv: bool,
                 lines: var seq[string],
                 warnings: var seq[Warning]) {.raises: [FitError].} =
  ## Append the lines for `data` to `lines` and any warnings to `warnings`.
  ## If reading fails part way, what was read before the error is kept.
  var r = initReader(p, data)
  try:
    for ev in r.events(p):
      if csv: lines.add csvLine(ev)
      elif ev.kind == evRecord: lines.add textLine(p, ev.record)
  finally:
    warnings.add r.warnings

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch fit ARGS`; returns the exit status.  (It does not use
  ## the database, so ignores the global options.)
  var
    csv = false
    profilePath = ""
    files: seq[string]
    i = 0
  while i < args.len:
    let a = args[i]
    if a in ["-h", "--help"]:
      stdout.say usage
      return exitOk
    elif a == "--csv":
      csv = true
    elif a == "--profile":
      inc i
      if i >= args.len:
        return usageError("nch fit", usage, "--profile needs a path")
      profilePath = args[i]
    elif a.startsWith("--profile="):
      profilePath = a["--profile=".len .. ^1]
    elif a.startsWith("-") and a != "-":
      return usageError("nch fit", usage, "unknown option " & a)
    else:
      files.add a
    inc i
  if files.len != 1:
    return usageError("nch fit", usage, "expected exactly one FILE")
  var
    lines: seq[string]
    warnings: seq[Warning]
    problem = ""
  try:
    let p =
      try: loadProfileOrDefault(profilePath)
      except NchError as e:
        return failure("nch fit", "cannot use the profile: " & e.msg)
    try:
      renderInto(p, readBytes(files[0]), csv, lines, warnings)
    except FitError as e:
      problem = e.msg  # report it after the output so far
  except NchError as e:
    return failure("nch fit", e.msg)
  except IOError as e:
    return failure("nch fit", e.msg)
  except OSError as e:
    return failure("nch fit", e.msg)
  try:
    for l in lines: stdout.write l & "\n"
  except IOError as e:
    return failure("nch fit", "cannot write the output: " & e.msg)
  for w in warnings:
    stderr.say "warning: offset " & $w.offset & ": " & w.msg & "\n"
  if problem.len > 0: failure("nch fit", problem) else: exitOk

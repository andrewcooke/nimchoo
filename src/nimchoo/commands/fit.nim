## `nch fit`: read a FIT file and dump it as text or as SDK-format CSV.

import std/[options, strutils, times]
import ../binary
import ../csvout
import ../decode
import ../defaultprofile
import ../profile
import ../tokens

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

proc run*(args: seq[string]): int =
  ## Entry point for `nch fit ARGS`; returns the exit status.
  var
    csv = false
    profilePath = ""
    files: seq[string]
    i = 0
  while i < args.len:
    let a = args[i]
    if a in ["-h", "--help"]:
      stdout.write usage
      return 0
    elif a == "--csv":
      csv = true
    elif a == "--profile":
      inc i
      if i >= args.len:
        stderr.write "nch fit: --profile needs a path\n" & usage
        return 2
      profilePath = args[i]
    elif a.startsWith("--profile="):
      profilePath = a["--profile=".len .. ^1]
    elif a.startsWith("-") and a != "-":
      stderr.write "nch fit: unknown option " & a & "\n" & usage
      return 2
    else:
      files.add a
    inc i
  if files.len != 1:
    stderr.write usage
    return 2
  var p: Profile
  try:
    p = loadProfileOrDefault(profilePath)
  except CatchableError as e:
    stderr.write "nch fit: cannot load profile: " & e.msg & "\n"
    return 1
  var data: seq[byte]
  try:
    data = readBytes(files[0])
  except IOError as e:
    stderr.write "nch fit: " & e.msg & "\n"
    return 1
  var
    lines: seq[string]
    warnings: seq[Warning]
  result = 0
  try:
    renderInto(p, data, csv, lines, warnings)
  except FitError as e:
    stderr.write "nch fit: " & e.msg & "\n"
    result = 1
  for l in lines: stdout.write l & "\n"
  for w in warnings:
    stderr.write "warning: offset " & $w.offset & ": " & w.msg & "\n"

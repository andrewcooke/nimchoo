## SDK-format CSV lines (as written by FitCSVTool with -defn) for decoder
## events.  Values are raw: enumerations stay numbers and times stay FIT
## seconds.  Arrays are joined with `|`.  Unknown message and field names
## are written as `unknown`.

import std/[sequtils, strutils]
import ./records

{.push raises: [].}

func quoted(s: string): string =
  '"' & s.replace("\"", "\"\"") & '"'

func cell(s: string): string =
  ## Quoted only if it has to be.
  if s.anyIt(it in {',', '"', '\n', '\r'}):
    quoted(s)
  else:
    s

func orUnknown(s: string): string =
  if s.len == 0: "unknown" else: s

func fmtValue*(f: FieldValue): string =
  ## The value(s) of a field as the SDK CSV shows them.
  case f.kind
  of vkInt:
    for i, v in f.ints:
      if i > 0:
        result.add '|'
      result.add $v
  of vkFloat:
    for i, v in f.floats:
      if i > 0:
        result.add '|'
      result.add $v
  of vkString:
    for i, v in f.strings:
      if i > 0:
        result.add '|'
      result.add v

func csvLine*(ev: Event): string =
  ## One CSV line (no newline) for a definition or a record.
  case ev.kind
  of evDefinition:
    result = "Definition," & $ev.local & "," & cell(orUnknown(ev.message))
    for f in ev.fields:
      result.add "," & cell(orUnknown(f.name)) & "," & $f.count & ","
  of evRecord:
    let r = ev.record
    result = "Data," & $r.local & "," & cell(orUnknown(r.name))
    for f in r.fields:
      result.add "," & cell(orUnknown(f.name)) & "," & quoted(fmtValue(f)) & "," &
        cell(f.units)

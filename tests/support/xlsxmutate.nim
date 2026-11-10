## Damage for xlsx files, for the fuzzers (tests/util/xlsx/test_fuzz.nim, tests/fit/test_profilefuzz.nim): either the
## zip container (zipmutate) or the xml of one part, which is put back in a container that is whole, so that the damage
## reaches the xml reader and the profile loader and is not just refused as a bad zip.

import std/[algorithm, random, tables]
import nimchoo/packages/util/zip/zipbytes
import ./[textmutate, xlsxbuilder, zipmutate, zips]

proc partsOf*(xlsx: string): seq[(string, string)] =
  ## The parts of an xlsx file (name, contents), in a fixed order.
  let entries = listEntries(xlsx)
  var names: seq[string]
  for name in entries.keys:
    names.add name
  names.sort()
  for name in names:
    result.add (name, readEntry(xlsx, name))

proc damagedXlsx*(r: var Rand, parts: seq[(string, string)]): string =
  ## A damaged xlsx file made from `parts`: half the time its container, half the time the xml of one part.
  if r.rand(1) == 0:
    r.damageZip(
      if r.rand(1) == 0:
        makeZip(parts, deflate = true)
      else:
        storedZip(parts)
    )
  else:
    var damaged = parts
    let i = r.rand(parts.high)
    damaged[i][1] = r.damageText(damaged[i][1])
    storedZip(damaged)

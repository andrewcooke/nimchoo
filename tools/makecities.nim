## Makes the list of places the program carries (src/nimchoo/places/cities.tsv.gz) from a
## GeoNames file.  Run it when you want a newer or different list:
##
##     curl -O https://download.geonames.org/export/dump/cities5000.zip && unzip cities5000.zip
##     nim c -r tools/makecities.nim cities5000.txt src/nimchoo/places/cities.tsv.gz
##
## (cities15000 and cities1000 work the same: the size of the list is the only difference.)
##
## Places GeoNames calls a "section of a populated place" (feature code PPLX: suburbs and
## districts such as Nunoa in Santiago) are left out, so that the nearest place to a ride is the
## city and not a district of it.  The tool also writes `cities.version` next to the list: its
## SHA-256, which goes into the checksum of the places fragment, so that a database made with
## another list is noticed (see db/store.nim).
##
## GeoNames data is licensed CC BY 4.0: see NOTICE.

import std/[os, strutils]
import checksums/sha2
import zippy

const
  columns = 19             # a GeoNames line has 19 tab-separated fields
  nameColumn = 1           # then, counting from 0: latitude 4, longitude 5, feature code 7,
                           # country 8, population 14
  leftOut = "PPLX"         # the feature code of a section of a populated place

proc main(): int =
  if paramCount() != 2:
    stderr.write "usage: makecities GEONAMES-FILE OUTPUT.tsv.gz\n"
    return 2
  var lines: seq[string]
  for line in lines(paramStr(1)):
    let f = line.split('\t')
    if f.len != columns:
      stderr.write "not a GeoNames line (" & $f.len & " fields): " & line[0 ..< min(line.len, 60)] & "\n"
      return 1
    if f[nameColumn].len == 0 or f[8].len != 2 or f[7] == leftOut: continue
    lines.add f[nameColumn] & "\t" & f[8] & "\t" & f[4] & "\t" & f[5] & "\t" & f[14]
  let packed = compress(lines.join("\n") & "\n", BestCompression, dfGzip)
  writeFile(paramStr(2), packed)
  var version = ""
  for c in secureHash(Sha_256, packed): version.add toLowerAscii(toHex(ord(c), 2))
  writeFile(parentDir(paramStr(2)) / "cities.version", version & "\n")
  echo lines.len, " places, ", getFileSize(paramStr(2)), " bytes, version ", version[0 ..< 12]
  0

quit main()

## Makes the list of places the program carries (src/nimchoo/places/cities.tsv.gz) from a
## GeoNames file.  Run it when you want a newer or different list:
##
##     curl -O https://download.geonames.org/export/dump/cities5000.zip && unzip cities5000.zip
##     nim c -r tools/makecities.nim cities5000.txt src/nimchoo/places/cities.tsv.gz
##
## (cities15000 and cities1000 work the same: the size of the list is the only difference.)
## GeoNames data is licensed CC BY 4.0: see NOTICE.

import std/[os, strutils]
import zippy

const
  columns = 19             # a GeoNames line has 19 tab-separated fields
  nameColumn = 1           # then, counting from 0: latitude 4, longitude 5, country 8, population 14

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
    if f[nameColumn].len == 0 or f[8].len != 2: continue
    lines.add f[nameColumn] & "\t" & f[8] & "\t" & f[4] & "\t" & f[5] & "\t" & f[14]
  writeFile(paramStr(2), compress(lines.join("\n") & "\n", BestCompression, dfGzip))
  echo lines.len, " places, ", getFileSize(paramStr(2)), " bytes"
  0

quit main()

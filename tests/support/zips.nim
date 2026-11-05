## Zip files made in memory, for tests: the format is simple (a local header and the data for each
## entry, then a central directory and an end record).

import zippy
import zippy/crc

func le16(x: int): string = $char(x and 0xff) & $char((x shr 8) and 0xff)

func le32(x: int): string = le16(x and 0xffff) & le16((x shr 16) and 0xffff)

proc makeZip*(entries: openArray[(string, string)], deflate = true): string =
  ## A zip holding the entries (name, contents), inflated or stored.
  var central = ""
  for (name, data) in entries:
    let packed = if deflate: compress(data, dataFormat = dfDeflate) else: data
    let compression = if deflate: 8 else: 0
    let crc = int(crc32(data))
    let offset = result.len
    result.add "PK\3\4" & le16(20) & le16(0) & le16(compression) & le16(0) & le16(0x21) & le32(crc) &
      le32(packed.len) & le32(data.len) & le16(name.len) & le16(0) & name & packed
    central.add "PK\1\2" & le16(20) & le16(20) & le16(0) & le16(compression) & le16(0) & le16(0x21) &
      le32(crc) & le32(packed.len) & le32(data.len) & le16(name.len) & le16(0) & le16(0) &
      le16(0) & le16(0) & le32(0) & le32(offset) & name
  let start = result.len
  result.add central
  result.add "PK\5\6" & le16(0) & le16(0) & le16(entries.len) & le16(entries.len) &
    le32(central.len) & le32(start) & le16(0)

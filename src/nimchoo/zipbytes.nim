## Reading a zip file from bytes in memory: the entries listed in its central directory, and an
## entry inflated (zippy only opens zips from a path).  Used for xlsx files and for downloads.
## Only stored and deflated entries are supported, and an entry that declares more than 256 MB is refused.

import std/tables
import zippy
import ./errors
import ./fit/bytes
export errors

{.push raises: [].}

type ZipEntry* = object
  compression*, compressedSize*, size*, offset*: int

func le(s: string, o, size: int): int {.raises: [ZipError].} =
  ## The `size` bytes at `o` as a little-endian integer.
  if not s.toOpenArrayByte(0, s.high).canRead(o, size):
    raiseZip("truncated zip file")
  int(getUint(s.toOpenArrayByte(0, s.high), o, size))

func u16(s: string, o: int): int {.raises: [ZipError].} = le(s, o, 2)

func u32(s: string, o: int): int {.raises: [ZipError].} = le(s, o, 4)

func listEntries*(z: string): Table[string, ZipEntry] {.raises: [ZipError].} =
  ## The central directory of a zip file.
  var eocd = -1
  var i = z.len - 22
  while i >= 0 and i >= z.len - 22 - 65535:
    if z[i] == 'P' and z[i + 1] == 'K' and z[i + 2] == '\5' and z[i + 3] == '\6':
      eocd = i
      break
    dec i
  if eocd < 0: raiseZip("not a zip file")
  var p = u32(z, eocd + 16)
  for _ in 0 ..< u16(z, eocd + 10):
    if u32(z, p) != 0x02014b50:
      raiseZip("bad zip central directory")
    let nameLen = u16(z, p + 28)
    if p + 46 + nameLen > z.len:
      raiseZip("truncated zip file")
    result[z[p + 46 ..< p + 46 + nameLen]] = ZipEntry(
      compression: u16(z, p + 10), compressedSize: u32(z, p + 20),
      size: u32(z, p + 24),
      offset: u32(z, p + 42))
    p += 46 + nameLen + u16(z, p + 30) + u16(z, p + 32)

const maxEntrySize* = 256 * 1024 * 1024  ## the default: larger declared sizes are refused

func extractEntry*(z: string, e: ZipEntry, limit = maxEntrySize): string {.raises: [ZipError].} =
  let p = e.offset
  if e.size > limit: raiseZip("zip entry too large")
  if u32(z, p) != 0x04034b50:
    raiseZip("bad zip local header")
  let start = p + 30 + u16(z, p + 26) + u16(z, p + 28)
  if start + e.compressedSize > z.len:
    raiseZip("truncated zip file")
  let raw = z[start ..< start + e.compressedSize]
  case e.compression
  of 0:
    if raw.len != e.size: raiseZip("zip entry has the wrong size")
    raw
  of 8:
    let data =
      try: uncompress(raw, dfDeflate)
      except ZippyError as ex:
        raiseZip("cannot inflate: " & ex.msg)
    if data.len != e.size: raiseZip("zip entry has the wrong size")
    data
  else:
    raiseZip("unsupported zip compression " & $e.compression)

func readEntry*(z, name: string, limit = maxEntrySize): string {.raises: [ZipError].} =
  ## The contents of the entry called `name` in the zip `z`.
  let entries = listEntries(z)
  if name notin entries: raiseZip("no " & name & " in the zip file")
  extractEntry(z, entries.getOrDefault(name), limit)

## Reading a zip file from bytes in memory: the entries listed in its central directory, and an
## entry inflated (zippy only opens zips from a path).  Used for xlsx files and for downloads.
## Only stored and deflated entries are supported, and an entry that declares more than 256 MB is refused.
##
## The limit is also on what is inflated, not only on what the header declares: zippy cannot stop at a size, so an
## `Inflater` can be given that does the inflating where a runaway is contained (`zipchild.nim`: a child process with
## a memory ceiling).  Without one the entry is inflated here, and only the declared size is a limit.

import std/tables
import zippy
import ./core/errors
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

func u16(s: string, o: int): int {.raises: [ZipError].} =
  le(s, o, 2)

func u32(s: string, o: int): int {.raises: [ZipError].} =
  le(s, o, 4)

func listEntries*(z: string): Table[string, ZipEntry] {.raises: [ZipError].} =
  ## The central directory of a zip file.
  var eocd = -1
  var i = z.len - 22
  while i >= 0 and i >= z.len - 22 - 65535:
    if z[i] == 'P' and z[i + 1] == 'K' and z[i + 2] == '\5' and z[i + 3] == '\6':
      eocd = i
      break
    dec i
  if eocd < 0:
    raiseZip("not a zip file")
  var p = u32(z, eocd + 16)
  for _ in 0 ..< u16(z, eocd + 10):
    if u32(z, p) != 0x02014b50:
      raiseZip("bad zip central directory")
    let nameLen = u16(z, p + 28)
    if p + 46 + nameLen > z.len:
      raiseZip("truncated zip file")
    result[z[p + 46 ..< p + 46 + nameLen]] = ZipEntry(
      compression: u16(z, p + 10),
      compressedSize: u32(z, p + 20),
      size: u32(z, p + 24),
      offset: u32(z, p + 42),
    )
    p += 46 + nameLen + u16(z, p + 30) + u16(z, p + 32)

const maxEntrySize* = 256 * 1024 * 1024 ## the default: larger declared sizes are refused

type Inflater* =
  proc(raw: string, size, limit: int): string {.closure, raises: [ZipError].}
  ## Inflates the deflated bytes `raw`, which should come to `size` bytes; ZipError if they come to more than `limit`
  ## or are damaged.

proc inflateHere*(raw: string, size, limit: int): string {.raises: [ZipError].} =
  ## The inflater that works in this process (zippy has no way to stop at `limit`: see the top of this file).
  try:
    result = uncompress(raw, dfDeflate)
  except ZippyError as ex:
    raiseZip("cannot inflate: " & ex.msg)
  if result.len > limit:
    raiseZip("zip entry too large")

proc extractEntry*(
    z: string, e: ZipEntry, limit = maxEntrySize, inflate: Inflater = nil
): string {.raises: [ZipError].} =
  ## The bytes of an entry (inflated, with `inflate` if given, and at most `limit`), checked against its declared size.
  let p = e.offset
  if e.size > limit:
    raiseZip("zip entry too large")
  if u32(z, p) != 0x04034b50:
    raiseZip("bad zip local header")
  let start = p + 30 + u16(z, p + 26) + u16(z, p + 28)
  if start + e.compressedSize > z.len:
    raiseZip("truncated zip file")
  let raw = z[start ..< start + e.compressedSize]
  case e.compression
  of 0:
    if raw.len != e.size:
      raiseZip("zip entry has the wrong size")
    raw
  of 8:
    let data =
      if inflate.isNil:
        inflateHere(raw, e.size, limit)
      else:
        inflate(raw, e.size, limit)
    if data.len != e.size:
      raiseZip("zip entry has the wrong size")
    data
  else:
    raiseZip("unsupported zip compression " & $e.compression)

proc readEntry*(
    z, name: string, limit = maxEntrySize, inflate: Inflater = nil
): string {.raises: [ZipError].} =
  ## The contents of the entry called `name` in the zip `z`.
  let entries = listEntries(z)
  if name notin entries:
    raiseZip("no " & name & " in the zip file")
  extractEntry(z, entries.getOrDefault(name), limit, inflate)

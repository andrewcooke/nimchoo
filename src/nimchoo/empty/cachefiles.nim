## The files commands have made in the cache (`user/`: maps, CSVs, pages).  They are made again
## when asked for, so emptying them loses nothing.  The files unpacked from the program
## (`system/`, which the author may have edited) and the server's token are not touched.

import std/os
import ../cache

{.push raises: [].}

type CacheFiles* = object
  count*: int
  bytes*: int64

func describe*(c: CacheFiles): string =
  ## "12 cache files (3 MB)", "1 cache file (12 kB)", "no cache files".
  if c.count == 0: return "no cache files"
  let size =
    if c.bytes >= 1_000_000: $(c.bytes div 1_000_000) & " MB"
    elif c.bytes >= 1_000: $(c.bytes div 1_000) & " kB"
    else: $c.bytes & " bytes"
  $c.count & (if c.count == 1: " cache file" else: " cache files") & " (" & size & ")"

proc cacheFiles*(dir: string): CacheFiles =
  ## What there is in the cache's `user/` directory (nothing if there is none).
  try:
    for kind, path in walkDir(userDir(dir)):
      if kind == pcFile:
        inc result.count
        result.bytes += getFileSize(path)
  except OSError:
    discard

proc removeCacheFiles*(dir: string): int =
  ## Delete them; returns how many were deleted.  A file that cannot be deleted is left.
  try:
    for kind, path in walkDir(userDir(dir)):
      if kind == pcFile:
        try:
          removeFile path
          inc result
        except OSError:
          discard
  except OSError:
    discard

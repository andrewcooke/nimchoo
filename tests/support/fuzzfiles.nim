## What the fuzzers share: the real FIT files they damage, and keeping an input that broke something.

import std/[algorithm, os, strutils]
import ./csvcompare

proc fitFiles*(minSize, maxSize: int, dirs: openArray[string]): seq[string] =
  ## The test files in `dirs` of the choochoo test data whose size is in `minSize .. maxSize` bytes, by name.
  for dir in dirs:
    for path in walkFiles(testRoot & "source/" & dir & "/*"):
      let size = int(getFileSize(path))
      if path.toLowerAscii.endsWith(".fit") and size >= minSize and size <= maxSize:
        result.add path
  result.sort()

proc signatureOf*(e: ref Exception): string =
  ## What identifies a failure, so that one bug is reported (and saved) once.
  $e.name & ": " & e.msg.splitLines()[0]

proc saveFailure*(target, source: string, round: int, data: seq[byte]): string =
  ## Write the input that failed to a temporary file and give its path (for the message).
  result =
    getTempDir() /
    ("fuzz-" & target & "-" & extractFilename(source) & "-" & $round & ".fit")
  var f = open(result, fmWrite)
  discard f.writeBytes(data, 0, data.len)
  f.close()

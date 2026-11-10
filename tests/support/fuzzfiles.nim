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

proc saveFailure*(
    target, source: string, round: int, data: seq[byte], ext = ".fit"
): string =
  ## Write the input that failed to a temporary file and give its path (for the message).
  result =
    getTempDir() /
    ("fuzz-" & target & "-" & extractFilename(source) & "-" & $round & ext)
  var f = open(result, fmWrite)
  discard f.writeBytes(data, 0, data.len)
  f.close()

proc savedFailures*(target: string, ext = ".fit"): seq[string] =
  ## The inputs that once broke `target` (kept in tests/data/fuzz/<target>/), so that a fixed bug stays fixed: those the
  ## level-1 tests saved (named for their extension) and those libFuzzer wrote (`nimble fuzz`: crash-HASH, oom-HASH ...).
  let dir = "tests/data/fuzz" / target
  for pattern in ["*" & ext, "crash-*", "oom-*", "timeout-*", "leak-*"]:
    for path in walkFiles(dir / pattern):
      result.add path
  result.sort()

func bytesOf*(s: string): seq[byte] =
  ## The bytes of a string (for saving an input that is text).
  result = newSeq[byte](s.len)
  for i, c in s:
    result[i] = byte(c)

## libFuzzer target: the zip reader.

import nimchoo/core/errors
import ./harness
import ../support/fuzzcheck

proc LLVMFuzzerTestOneInput(
    data: ptr UncheckedArray[byte], len: csize_t
): cint {.exportc, cdecl.} =
  try:
    useZip(asString(data, len))
  except ZipError:
    discard
  0

## libFuzzer target: the profile loader (the xlsx reader, and then the Types and Messages sheets).

import nimchoo/core/errors
import ./harness
import ../support/fuzzcheck

proc LLVMFuzzerTestOneInput(
    data: ptr UncheckedArray[byte], len: csize_t
): cint {.exportc, cdecl.} =
  try:
    loads(asString(data, len))
  except ProfileError, XlsxError:
    discard
  0

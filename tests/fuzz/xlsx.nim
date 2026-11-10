## libFuzzer target: the xlsx reader.

import nimchoo/core/errors
import ./harness
import ../support/fuzzcheck

proc LLVMFuzzerTestOneInput(
    data: ptr UncheckedArray[byte], len: csize_t
): cint {.exportc, cdecl.} =
  try:
    useXlsx(asString(data, len))
  except XlsxError:
    discard
  0

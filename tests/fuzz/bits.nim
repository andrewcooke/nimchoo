## libFuzzer target: `decodeBits`, the list of activities of a map address (see tests/support/fuzzcheck.nim for what must hold).

import ./harness
import ../support/fuzzcheck

proc LLVMFuzzerTestOneInput(
    data: ptr UncheckedArray[byte], len: csize_t
): cint {.exportc, cdecl.} =
  let problem = bitsProblemAny(asString(data, len))
  doAssert problem == "", problem
  0

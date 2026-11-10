## libFuzzer target: the server's request checks (an address; see tests/support/fuzzcheck.nim for what must hold).

import ./harness
import ../support/fuzzcheck
import ../support/webpages

let pages = testPages

proc LLVMFuzzerTestOneInput(
    data: ptr UncheckedArray[byte], len: csize_t
): cint {.exportc, cdecl.} =
  let problem = requestProblem(asString(data, len), pages)
  doAssert problem == "", problem
  0

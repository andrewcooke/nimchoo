## libFuzzer target: the server's request checks (an address; see tests/support/fuzzcheck.nim for what must hold).

import ./harness
import ../support/fuzzcheck
import ../../src/nimchoo/packages/ff/web
import ../../src/nimchoo/packages/map/web as mapWeb

let pages = @[mapPage("map"), ffPage("ff")]

proc LLVMFuzzerTestOneInput(
    data: ptr UncheckedArray[byte], len: csize_t
): cint {.exportc, cdecl.} =
  let problem = requestProblem(asString(data, len), pages)
  doAssert problem == "", problem
  0

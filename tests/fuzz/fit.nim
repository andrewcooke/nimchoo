## libFuzzer target: the FIT reader as `nch fit` uses it, as text and as CSV.

import nimchoo/core/errors
import nimchoo/packages/fit/command
import nimchoo/packages/fit/load
import nimchoo/packages/util/warnings/warnings
import ./harness

let profile = loadProfile("../choochoo/data/sdk/Profile.xlsx")
  # (once: a test tool may have module-level state, and loading takes 30 ms)

proc LLVMFuzzerTestOneInput(
    data: ptr UncheckedArray[byte], len: csize_t
): cint {.exportc, cdecl.} =
  let bytes = asBytes(data, len)
  for csv in [false, true]:
    var lines: seq[string]
    var warnings: seq[Warning]
    try:
      renderInto(profile, bytes, csv, lines, warnings)
    except FitError:
      discard
  0

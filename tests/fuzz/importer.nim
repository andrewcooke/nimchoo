## libFuzzer target: the importer's reader of FIT files (`readActivities`), with and without the heart-rate channel.

import nimchoo/core/errors
import nimchoo/packages/fit/load
import nimchoo/packages/importer/extract
import nimchoo/packages/util/warnings/warnings
import ./harness

let profile = loadProfile("../choochoo/data/sdk/Profile.xlsx")

proc LLVMFuzzerTestOneInput(
    data: ptr UncheckedArray[byte], len: csize_t
): cint {.exportc, cdecl.} =
  let bytes = asBytes(data, len)
  for channels in [@[], @["heart_rate"]]:
    var ws: seq[Warning]
    try:
      discard readActivities(profile, bytes, ws, channels)
    except FitError, ImportError:
      discard
  0

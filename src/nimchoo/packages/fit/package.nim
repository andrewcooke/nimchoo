## FIT files: the decoder, the profile that says what the fields mean, and `nch fit`.
##
## The decoder reads the records of a FIT file into messages and fields (`reader`, `decode`, `basetype`), checked against the
## SDK's own CSV output (`nimble csvreport`).  The profile, which the SDK ships as a spreadsheet (read by `xlsx`), is loaded
## into types, scales, offsets and sub-fields (`load`, `model`).  `nch fit FILE` prints a file as text or as SDK-format CSV.
## A corrupt file is a `FitError`, never a crash: the decoder is fuzzed (HISTORY.md).

import ../../core/manifest
import ./command

const package* = Package(
  depends: @["args", "bundle", "bytes", "lookup", "ui", "warnings", "xlsx"],
  fragments: @[],
  commands: @[
    CommandDecl(
      name: "fit",
      summary: "read a FIT file and print it",
      run: command.run,
      options: command.options,
    )
  ],
)

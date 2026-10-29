## The FIT profile built into the executable (data/Profile.xlsx), so that
## tools work without `--profile`.

import std/[os, tempfiles]
import ./profile

const embedded = staticRead("../../data/Profile.xlsx")

proc loadDefaultProfile*(): Profile =
  ## The embedded profile.  (The xlsx reader only loads from a path, so this
  ## goes via a temporary file.)
  let (f, path) = createTempFile("nch-profile-", ".xlsx")
  try:
    f.write embedded
    f.close()
    result = loadProfile(path)
  finally:
    removeFile(path)

proc loadProfileOrDefault*(path: string): Profile =
  ## The profile at `path`, or the embedded one if `path` is empty.
  if path.len == 0: loadDefaultProfile() else: loadProfile(path)

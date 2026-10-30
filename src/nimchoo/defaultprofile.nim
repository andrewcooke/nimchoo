## The FIT profile built into the executable (data/Profile.xlsx), so that
## tools work without `--profile`.

import ./profile

const embedded = staticRead("../../data/Profile.xlsx")

proc loadDefaultProfile*(): Profile =
  ## The embedded profile.
  loadProfileFromBytes(embedded)

proc loadProfileOrDefault*(path: string): Profile =
  ## The profile at `path`, or the embedded one if `path` is empty.
  if path.len == 0: loadDefaultProfile() else: loadProfile(path)

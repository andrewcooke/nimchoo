## The FIT profile built into the executable (data/Profile.xlsx), so that
## tools work without `--profile`.

import ./load

{.push raises: [].}

const embedded = staticRead("../../../data/Profile.xlsx")

proc loadDefaultProfile*(): Profile {.raises: [ProfileError, XlsxError].} =
  ## The embedded profile.
  loadProfileFromBytes(embedded)

proc loadProfileOrDefault*(path: string): Profile {.raises: [ProfileError, XlsxError, IOError].} =
  ## The profile at `path`, or the embedded one if `path` is empty.
  if path.len == 0: loadDefaultProfile() else: loadProfile(path)

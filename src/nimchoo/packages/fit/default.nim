## The FIT profile built into the executable (Profile.xlsx, beside this file), so that tools work without
## `--profile`.  It is also kept as a file in the cache's `system/` part (see bundle/unpack.nim):
## a file the author puts there instead (say a newer SDK's) is used in its place.

import ../bundle/unpack
import ./load

{.push raises: [].}

const embedded = staticRead("Profile.xlsx")
const profileBundle* = Bundle(name: "Profile.xlsx", data: embedded)

proc loadDefaultProfile*(): Profile {.raises: [ProfileError, XlsxError].} =
  ## The profile to use when none is asked for: the file in the cache's `system/` part (the
  ## built-in one, unpacked, or the author's).  An error if the author's cannot be read.
  loadProfileFromBytes(resolve(profileBundle).data)

proc defaultProfile*(): tuple[profile: Profile, note: string, bytes: string] =
  ## `loadDefaultProfile`, but if the author's profile cannot be used the built-in one is, with a
  ## note saying so.  The note also says when the author's is the one in use ("" otherwise).
  let r = resolve(profileBundle)
  result.bytes = r.data # (the spreadsheet in use: another thread can load its own copy)
  try:
    result.profile = loadProfileFromBytes(r.data)
    if r.source == soCustom:
      result.note = "using the profile " & r.path & " (not the built-in one)"
  except NchError as e:
    if r.source != soCustom:
      raiseAssert "the built-in profile does not load: " & e.msg # a bug
    result.bytes = embedded
    try:
      result.profile = loadProfileFromBytes(embedded)
    except NchError as e2:
      raiseAssert "the built-in profile does not load: " & e2.msg # a bug
    result.note =
      "the profile " & r.path & " cannot be used (" & e.msg & "): using the built-in one"

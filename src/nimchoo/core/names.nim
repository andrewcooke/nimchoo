## How package names are compared: as Nim compares names (the case of every letter but the first, and underscores,
## do not count).

import std/strutils

{.push raises: [].}

func normalised*(name: string): string =
  ## A name as Nim compares them: ignoring case (after the first letter) and underscores.
  if name.len == 0:
    return ""
  result = name[0 .. 0] & name[1 ..^ 1].toLowerAscii.replace("_", "")

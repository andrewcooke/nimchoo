## How package names are compared: as Nim compares names (the case of every letter but the first, and underscores,
## do not count).

import std/strutils

{.push raises: [].}

func normalised*(name: string): string =
  ## A name as Nim compares them: ignoring case (after the first letter) and underscores.
  if name.len == 0:
    return ""
  result = name[0 .. 0] & name[1 ..^ 1].toLowerAscii.replace("_", "")

func sameName*(a, b: string): bool =
  ## Whether two names are one, as Nim compares names (`normalised`): the one comparison of the names of packages.
  a.normalised == b.normalised

func hasName*(names: openArray[string], name: string): bool =
  ## Whether `name` is one of `names`, as Nim compares names.
  for n in names:
    if sameName(n, name):
      return true
  false

## Putting the packages in order: the logic behind the generated `registry.nim`.  Pure, so it is tested with
## made-up packages; the generated file calls it at compile time, where an error stops the build.

import std/[algorithm, strutils, tables]
import ./errors
import ./package

{.push raises: [].}

func normalised*(name: string): string =
  ## A name as Nim compares them: ignoring case (after the first letter) and underscores.
  if name.len == 0:
    return ""
  result = name[0 .. 0] & name[1 ..^ 1].toLowerAscii.replace("_", "")

func visit(
    name: string,
    byName: Table[string, Registered],
    state: var Table[string, int],
    path: var seq[string],
    order: var seq[Registered],
) {.raises: [PackageError].} =
  ## Depth first: a package is added to `order` after everything it depends on.  `state`: absent, not
  ## visited; 1, on the path now; 2, done.
  let key = name.normalised
  doAssert key in byName # (the caller checked)
  let current = byName.getOrDefault(key)
  case state.getOrDefault(key, 0)
  of 2:
    return
  of 1:
    let start = path.find(current.name)
    raisePackage("a cycle of dependencies: " & (path[start ..^ 1] & name).join(" -> "))
  else:
    discard
  state[key] = 1
  path.add current.name
  for d in current.package.depends.sortedByIt(it.normalised):
    if d.normalised notin byName:
      raisePackage(
        "package '" & current.name & "' depends on '" & d & "', which there is not"
      )
    visit(d, byName, state, path, order)
  discard path.pop
  state[key] = 2
  order.add current

func inDependencyOrder*(
    packages: seq[Registered]
): seq[Registered] {.raises: [PackageError].} =
  ## The packages with each after the packages it depends on (otherwise by name).  Raises `PackageError`
  ## for a name used twice (compared as Nim does), a dependency that is not there, or a cycle (the
  ## message gives the cycle).
  var byName: Table[string, Registered]
  for p in packages:
    let key = p.name.normalised
    if key in byName:
      raisePackage(
        "two packages are called '" & byName.getOrDefault(key).name & "' and '" & p.name &
          "' (names are compared as Nim compares: not the case of the first letter, nor underscores)"
      )
    byName[key] = p
  var state: Table[string, int]
  var path: seq[string]
  for p in packages.sortedByIt(it.name.normalised):
    visit(p.name, byName, state, path, result)

func collectCommands*(
    packages: seq[Registered]
): seq[CommandDecl] {.raises: [PackageError].} =
  ## The commands of all the packages, by name.  Raises `PackageError` for a name two commands share.
  var seen: Table[string, string] # command -> the package that provides it
  for p in packages:
    for c in p.package.commands:
      if c.name in seen:
        raisePackage(
          "command '" & c.name & "' is provided by both '" & seen.getOrDefault(c.name) &
            "' and '" & p.name & "'"
        )
      seen[c.name] = p.name
      result.add c
  result = result.sortedByIt(it.name)

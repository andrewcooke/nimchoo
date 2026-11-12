## Putting the packages in order: the logic behind the generated `registry.nim`.  Pure, so it is tested with
## made-up packages; the generated file calls it at compile time, where an error stops the build.

import std/[algorithm, strutils, tables]
import ./errors
import ./[access, extension, fragment, names, ownership, manifest]
export names

{.push raises: [].}

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

const builtinCommands* = ["packages"]
  ## commands `nch` provides itself (a package cannot, for they need the registry); no package may take these names

func collectCommands*(
    packages: seq[Registered]
): seq[CommandDecl] {.raises: [PackageError].} =
  ## The commands of all the packages, by name.  Raises `PackageError` for a name two commands share.
  var seen: Table[string, string] # command -> the package that provides it
  for p in packages:
    for c in p.package.commands:
      if c.name in builtinCommands:
        raisePackage(
          "package '" & p.name & "' provides the command '" & c.name &
            "', which `nch` provides itself"
        )
      if c.name in seen:
        raisePackage(
          "command '" & c.name & "' is provided by both '" & seen.getOrDefault(c.name) &
            "' and '" & p.name & "'"
        )
      seen[c.name] = p.name
      result.add c
  result = result.sortedByIt(it.name)

func commandList*(commands: seq[CommandDecl]): string =
  ## The lines of the usage text that name the commands (they are in the order given, by name), each name
  ## padded to a column.
  for c in commands:
    result.add "  " & c.name.alignLeft(11) & " " & c.summary & "\n"

func collectPoints*(
    packages: seq[Registered]
): seq[tuple[owner: string, point: PointDecl]] {.raises: [PackageError].} =
  ## The extension points the packages define, with the package that defines each.  Raises `PackageError` for a point
  ## whose name does not start with its package's ("importer/after") or that two packages define.
  var seen: Table[string, string]
  for p in packages:
    for d in p.package.defines:
      if not d.name.startsWith(p.name & "/"):
        raisePackage(
          "package '" & p.name & "' defines the point '" & d.name &
            "', whose name must start with '" & p.name & "/'"
        )
      if d.name in seen:
        raisePackage(
          "the point '" & d.name & "' is defined by both '" & seen.getOrDefault(d.name) &
            "' and '" & p.name & "'"
        )
      seen[d.name] = p.name
      result.add (p.name, d)

proc collectExtensions*(
    packages: seq[Registered]
): Extensions {.raises: [PackageError].} =
  ## What the packages contribute, added in the order given (dependency order), each stamped with its package.
  ## Raises `PackageError` when two points of one name hold different types, and for a contribution to a point that
  ## no package defines.
  var typeOf: Table[string, (string, string)]
    # point -> (type, the package that first used it)
  var defined: seq[string]
  for p in packages:
    for d in p.package.defines:
      defined.add d.name
  for p in packages:
    if p.package.contributes == nil:
      continue
    for c in p.package.contributes():
      if c.point notin defined:
        raisePackage(
          "package '" & p.name & "' contributes to the point '" & c.point &
            "', which no package defines (`defines:` in its package.nim)"
        )
      c.source = p.name
      let known = typeOf.getOrDefault(c.point, ("", ""))
      if known[0].len > 0 and known[0] != c.typeName:
        raisePackage(
          "extension point '" & c.point & "' is given a " & c.typeName & " by '" & p.name &
            "' but a " & known[0] & " by '" & known[1] & "'"
        )
      typeOf[c.point] = (
        c.typeName,
        if known[0].len > 0:
          known[1]
        else:
          p.name,
      )
      result.add c

func accessOf*(
    packages: seq[Registered], fragments: seq[Fragment], mode = amEnforce
): Access {.raises: [PackageError].} =
  ## The access rules for these packages (dev/PACKAGES.md, "The access model"): who owns which table, from the
  ## fragments, and what each package declares it uses.
  var depends: Table[string, seq[string]]
  for p in packages:
    depends[p.name] = p.package.depends
  newAccess(mode, tableOwners(fragments), depends, parentTables(fragments))

func collectFragments*(
    packages: seq[Registered]
): seq[Fragment] {.raises: [PackageError].} =
  ## The fragments of all the packages, each package's in its order, the packages in the order given (dependency
  ## order: a package whose tables refer to another's comes after it).  Raises `PackageError` for a fragment that
  ## is not named after its package, and for a table that refers (by `references`) to one of a package that this
  ## package does not depend on: SQLite would not notice when the table is made, only when a row is deleted.
  for p in packages:
    for f in p.package.fragments:
      if f.ownerName.normalised != p.name.normalised:
        raisePackage(
          "package '" & p.name & "' lists the fragment '" & f.name &
            "', which belongs to '" & f.ownerName & "'"
        )
      result.add f
  let owners = tableOwners(result)
  var depends: Table[string, seq[string]]
  for p in packages:
    var names: seq[string]
    for d in p.package.depends:
      names.add d.normalised
    depends[p.name.normalised] = names
  for child, parents in parentTables(result):
    let owner = owners.getOrDefault(child, "").normalised
    for parent in parents:
      let theirs = owners.getOrDefault(parent, "").normalised
      if owner.len > 0 and theirs.len > 0 and theirs != owner and
          theirs notin depends.getOrDefault(owner):
        raisePackage(
          "table '" & child & "' of '" & owner & "' refers to '" & parent & "' of '" &
            theirs & "', which '" & owner & "' does not depend on"
        )

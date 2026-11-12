## Who may touch which table (dev/PACKAGES.md, "The access model: dependencies are grants").  A package may read the
## tables it owns, those of the packages it `depends` on, and those of `db` (the user table and the rest every
## package refers to); it may write, and change the definition of, only the tables it owns.  This module is the
## rule and nothing else: it is pure.  `packages/db/access.nim` asks it while a statement is prepared, with the
## package the statement was written in, and refuses what it forbids.
##
## A mistake-catcher, not a security boundary: a package is source that is compiled in (see dev/PACKAGES.md).

import std/[options, sets, strutils, tables]
import ./[names, ownership]

{.push raises: [].}

const sharedOwner* = "db" ## the owner of the tables every package may read

type
  AccessMode* = enum
    amOff ## nothing is checked
    amEnforce ## what is refused is a `StoreError`

  Action* = enum
    acRead
    acWrite ## insert, update, delete
    acDefine ## create, alter, drop

  Access* = ref object ## The rules, made once when `nch` starts and never changed.
    mode*: AccessMode
    owners: Table[string, string] # table -> package
    parents: Table[string, seq[string]] # table -> the tables it refers to (foreign keys)
    depends: Table[string, HashSet[string]]
      # package -> the packages it declares (all normalised)

func newAccess*(
    mode: AccessMode,
    owners: Table[string, string],
    depends: Table[string, seq[string]],
    parents = initTable[string, seq[string]](),
): Access =
  ## `owners`: table -> the package that makes it (`tableOwners`).  `depends`: package -> its `depends`.
  ## `parents`: table -> the tables it has foreign keys to (`parentTables`).
  result = Access(mode: mode, owners: owners, parents: parents)
  for package, names in depends:
    var declared = initHashSet[string]()
    for n in names:
      declared.incl n.normalised
    result.depends[package.normalised] = declared

func ownerOf*(a: Access, table: string): Option[string] =
  ## The package that owns `table` (none: SQLite's own tables and SpatiaLite's, which nobody made by DDL).
  ownership.ownerOf(table, a.owners)

func baseTable(a: Access, table: string): string =
  ## `table`, or for a SpatiaLite spatial index the table it indexes.
  let name = table.toLowerAscii
  if name in a.owners or not name.startsWith("idx_"):
    return name
  result = name
  var best = 0
  for t in a.owners.keys:
    if t.len > best and name.startsWith("idx_" & t & "_"):
      best = t.len
      result = t

func refersTo(a: Access, table: string, written: seq[string]): bool =
  ## Whether `table` has a foreign key, directly or through other tables, to one of `written`: a row of it goes
  ## when a row of the parent does (`on delete cascade`).
  var seen = initHashSet[string]()
  var todo = @[a.baseTable(table)]
  while todo.len > 0:
    let t = todo.pop
    for p in a.parents.getOrDefault(t):
      if p in written:
        return true
      if not seen.containsOrIncl(p):
        todo.add p

func isLookedUpBy(a: Access, table: string, written: seq[string]): bool =
  ## Whether `table` is the parent of a table that a cascade from `written` reaches: deleting a row of the child
  ## makes SQLite look at its other parents.
  let t = a.baseTable(table)
  for child, parents in a.parents:
    if t in parents and a.refersTo(child, written):
      return true

func refusal*(
    a: Access,
    caller: string,
    action: Action,
    table: string,
    written: seq[string] = @[],
    contributors: seq[string] = @[],
): Option[string] =
  ## Why `caller` (a package; "": code outside the packages, which is not checked) may not do `action` to
  ## `table`; none if it may.  `written`: the tables the same statement writes directly, whose foreign keys carry
  ## it further: what a cascade does to the tables that refer to them (and the reading of their other parents) is
  ## the database's doing, not the caller's.  `contributors`: the other packages that wrote pieces of the statement
  ## (an activity criterion that another package offers): a read is allowed if any of them may make it; a write
  ## or a change of definition is the caller's alone, so that a contributed piece cannot make the caller write the
  ## tables of the contributor.
  if caller.len == 0:
    return none(string)
  if action == acRead:
    for c in contributors:
      if c.normalised != caller.normalised and
          a.refusal(c, acRead, table, written).isNone:
        return none(string)
  let owner = a.ownerOf(table)
  if owner.isNone or owner.get.normalised == caller.normalised:
    return none(string)
  if written.len > 0 and (
    a.refersTo(table, written) or (action == acRead and a.isLookedUpBy(table, written))
  ):
    return none(string)
  let theirs = owner.get
  case action
  of acRead:
    if theirs == sharedOwner or
        theirs.normalised in a.depends.getOrDefault(caller.normalised):
      return none(string)
    some(
      "package '" & caller & "' reads table '" & table & "' of '" & theirs &
        "', which it does not depend on" & (
        if contributors.len > 0:
        " (nor do the packages that wrote pieces of the statement: " &
          contributors.join(", ") & ")"
        else: ""
      )
    )
  of acWrite:
    some("package '" & caller & "' writes table '" & table & "' of '" & theirs & "'")
  of acDefine:
    some(
      "package '" & caller & "' changes the definition of table '" & table & "' of '" &
        theirs & "'"
    )

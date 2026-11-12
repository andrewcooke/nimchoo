## Which package owns which table.  Nobody lists it: the package that makes a table owns it, and what a
## package makes is read from its fragments, which are plain DDL by rule (dev/PACKAGES.md, "Ownership is
## inferred").  A scan of the text is enough for `create table` and `alter table ... rename to`; what it cannot
## see (SpatiaLite makes `idx_activity_start` when a function is called) is found by a test that applies the
## fragments to SQLite and compares (tests/core/test_ownership.nim).  Pure, so it can run at compile time.

import std/[options, strutils, tables]
import ./errors
import ./fragment

{.push raises: [].}

type
  TableEventKind* = enum
    teCreate
    teRename

  TableEvent* = object ## what a piece of DDL does to the set of tables
    kind*: TableEventKind
    name*: string ## the table made, or the new name of a renamed one (lower case)
    renamed*: string ## for a rename, the old name

func withoutComments(sql: string): string =
  ## `-- ...` and `/* ... */` removed.
  var i = 0
  while i < sql.len:
    if sql.continuesWith("--", i):
      while i < sql.len and sql[i] != '\n':
        inc i
    elif sql.continuesWith("/*", i):
      i += 2
      while i < sql.len and not sql.continuesWith("*/", i):
        inc i
      i += 2
    else:
      result.add sql[i]
      inc i

func tableName(token: string): string =
  ## A name as written (maybe quoted, maybe with its schema `main.`), in lower case.
  result = token.toLowerAscii.strip(chars = {'"', '`', '[', ']', '\''})
  let dot = result.rfind('.')
  if dot >= 0:
    result = result[dot + 1 ..^ 1].strip(chars = {'"', '`', '[', ']', '\''})

func tableEvents*(sql: string): seq[TableEvent] =
  ## The tables a script makes and renames, in order.  Indexes, views and triggers are not tables here;
  ## an index belongs to the owner of its table, so it is no question of ownership.
  for statement in sql.withoutComments.split(';'):
    let words = statement.replace('(', ' ').replace(',', ' ').splitWhitespace
    var i = 0
    if words.len >= 3 and words[0].toLowerAscii == "create":
      i = 1
      if words[i].toLowerAscii == "virtual":
        inc i
      if i < words.len and words[i].toLowerAscii == "table":
        inc i
        if i + 2 < words.len and words[i].toLowerAscii == "if" and
            words[i + 1].toLowerAscii == "not" and words[i + 2].toLowerAscii == "exists":
          i += 3
        if i < words.len:
          result.add TableEvent(kind: teCreate, name: words[i].tableName)
    elif words.len >= 6 and words[0].toLowerAscii == "alter" and
        words[1].toLowerAscii == "table" and words[3].toLowerAscii == "rename" and
        words[4].toLowerAscii == "to":
      result.add TableEvent(
        kind: teRename, name: words[5].tableName, renamed: words[2].tableName
      )

func parentTables*(fragments: seq[Fragment]): Table[string, seq[string]] =
  ## Table -> the tables it refers to by `references` (a foreign key), read from `create table` and `alter table`
  ## in the fragments.  A test compares it with what SQLite says (`pragma foreign_key_list`).
  for f in fragments:
    for statement in f.sql.withoutComments.split(';'):
      let words =
        statement.replace('(', ' ').replace(')', ' ').replace(',', ' ').splitWhitespace
      var child = ""
      if words.len >= 3 and words[0].toLowerAscii == "create":
        var i = 1
        if words[i].toLowerAscii == "virtual":
          inc i
        if i < words.len and words[i].toLowerAscii == "table":
          inc i
          if i + 2 < words.len and words[i].toLowerAscii == "if" and
              words[i + 1].toLowerAscii == "not" and
              words[i + 2].toLowerAscii == "exists":
            i += 3
          if i < words.len:
            child = words[i].tableName
      elif words.len >= 3 and words[0].toLowerAscii == "alter" and
          words[1].toLowerAscii == "table":
        child = words[2].tableName
      if child.len == 0:
        continue
      for i in 0 ..< words.len - 1:
        if words[i].toLowerAscii == "references":
          let parent = words[i + 1].tableName
          if parent notin result.getOrDefault(child):
            result.mgetOrPut(child, @[]).add parent

func ownerName*(f: Fragment): string =
  ## The package a fragment belongs to: the directory part of its name, `climbs` in `climbs/001-schema.sql`.
  f.name.split('/')[0]

func tableOwners*(
    fragments: seq[Fragment]
): Table[string, string] {.raises: [PackageError].} =
  ## Table name -> the package that makes it, from the fragments in the order they are applied.  Raises
  ## `PackageError` for a table that two fragments make, and for a rename of a table the package does not own.
  for f in fragments:
    let owner = f.ownerName
    for e in tableEvents(f.sql):
      case e.kind
      of teCreate:
        if e.name in result:
          raisePackage(
            "table '" & e.name & "' is made by '" & f.name & "' and was made by '" &
              result.getOrDefault(e.name) & "'"
          )
        result[e.name] = owner
      of teRename:
        if result.getOrDefault(e.renamed) != owner:
          raisePackage(
            "'" & f.name & "' renames '" & e.renamed & "', which '" & owner &
              "' does not make"
          )
        result.del e.renamed
        result[e.name] = owner

func ownerOf*(table: string, owners: Table[string, string]): Option[string] =
  ## The package that owns `table`: the one that made it, or, for a SpatiaLite spatial index
  ## (`idx_<table>_<column>` and its `_node`, `_parent` and `_rowid`), the one that made `<table>`.
  let name = table.toLowerAscii
  if name in owners:
    return some(owners.getOrDefault(name))
  if name.startsWith("idx_"):
    var best = ""
    for t in owners.keys:
      if name.startsWith("idx_" & t & "_") and t.len > best.len:
        best = t
    if best.len > 0:
      return some(owners.getOrDefault(best))

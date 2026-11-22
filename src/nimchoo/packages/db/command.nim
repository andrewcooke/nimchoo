## `nch db`: the database file.  With no arguments it says where it is, how big, and what it holds,
## table by table (`holding.nim`); `--delete` deletes it, and
## with it the data of every user (the cache, which can be made again, is `nch cache`).  It asks first (`core/ask`: `[yN]`; `-y` answers yes; with no terminal and no `-y`, nothing is deleted).

import std/[options, os, strformat]
import db_connector/db_sqlite
import ../../core/[access, ask, globals, ruled]
import ../util/args/[args, usage]
import ../ui/units
import ../../core/errors
import ../../core/logfile
import ../ui/[style]
import ./statement
import ./[holding, params, store]

{.push raises: [].}

const commandName* = "db" ## what the user types after `nch`

proc options*(g: Globals): seq[OptDoc] {.nimcall, raises: [].} =
  ## The options of `nch db`, described (for tab completion).
  dbSpec().docs

const
  synopsis = """usage: nch [--db PATH] db
       nch [--db PATH] db --delete"""
  intro = @[
    ~"Without options, say where the database is and how big, and what it holds, table by table: the package that owns each, how many rows, how much of the file it takes (with its indexes), the tables it refers to, and the other packages that may read it."
  ]

proc usageText*(width: int): seq[Line] =
  ## The usage: the synopsis, the introduction and the options, wrapped to `width`.
  usageOf(synopsis, width, intro, dbSpec().docs)

proc size(path: string): int64 =
  ## The database file with its journal files.
  for suffix in ["", "-journal", "-wal", "-shm"]:
    try:
      if fileExists(path & suffix):
        result += getFileSize(path & suffix)
    except OSError:
      discard

proc freeSpace(path: string): Option[string] =
  ## ", 12 MB free" when a deleted row's space is waiting to be reused or given back; none if there is none or it is unknown.
  try:
    let db = open(path, "", "", "")
    defer:
      db.close()
    let free =
      db.scalar(int64, "pragma freelist_count") * db.scalar(int64, "pragma page_size")
    if free > 0:
      result = some(", " & humanBytes(free) & " free")
  except DbError, StoreError:
    discard

proc tablesLines(
    g: Globals, path: string, width: int
): seq[Line] {.raises: [StoreError].} =
  ## What the database at `path` holds, as a table, then a line for the tables of SQLite and SpatiaLite.
  var db: DbConn
  try:
    db = open(path, "", "", "")
  except DbError as e:
    raiseStore(fmt"cannot open {path}: {e.msg}")
  defer:
    try:
      db.close()
    except DbError:
      discard # (it was only read: nothing is lost)
  db.execute("pragma query_only = 1") # (a look: nothing is written)
  let access = g.access
  let h = holding(
    db,
    proc(table: string): Option[string] {.raises: [].} =
      (if access.isNil: none(string) else: access.ownerOf(table)),
  )
  var rows: seq[seq[Line]]
  for t in h.tables:
    var refers: Line
    for k, r in t.refersTo:
      if k > 0:
        refers.add ~", "
      refers.add ~"`{r}`"
    var readers: Line
    if t.owner.isSome and t.owner.get == sharedOwner:
      readers = plain("every package")
    elif not access.isNil:
      for k, r in access.readersOf(t.name):
        if k > 0:
          readers.add ~", "
        readers.add ~"`{r}`"
    rows.add @[
      ~"`{t.name}`",
      (if t.owner.isSome: ~"`{t.owner.get}`" else: plain("-")),
      plain(count(t.rows)),
      plain(humanBytes(t.bytes)),
      (if refers.len == 0: plain("-") else: refers),
      (if readers.len == 0: plain("-") else: readers),
    ]
  result = ruled(
    @["table", "owner package", "rows", "size", "refers to", "packages with access"],
    rows,
    width,
    right = {2, 3},
  )
  if h.others > 0:
    result.add plain("")
    result.add plain(
      fmt"and {h.others} tables of SQLite and SpatiaLite and the record of the fragments, {humanBytes(h.othersBytes)}"
    )

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch db ARGS`; returns the exit status.
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    g.showAll osOut, usageText(g.textWidth(osOut))
    return exitOk
  of pkProblem:
    return usageError(g, "nch db", usageText(g.textWidth(osErr)), parsed.why)
  of pkUnit:
    return unitRetry(g, "nch db", parsed.fix, run)
  of pkOk:
    discard
  let p = parsed.params
  let path = resolveDbPath(g.dbPath)
  if not fileExists(path):
    g.show(osOut, ~"no database at <file {path}>")
    return exitOk
  if p.action == daShow:
    let free = freeSpace(path).get("")
    g.show(osOut, ~"<file {path}> ({humanBytes(size(path))}{free})")
    g.show(osOut, plain(""))
    try:
      g.showAll(osOut, tablesLines(g, path, g.textWidth(osOut)))
    except StoreError as e:
      return failure(g, "nch db", e.msg)
    return exitOk
  let what =
    fmt"the database {path} ({humanBytes(size(path))}) with the data of every user"
  if not confirmDelete(g, what, parsed.yes):
    return exitFailure
  try:
    for suffix in ["", "-journal", "-wal", "-shm"]:
      removeFile path & suffix
  except OSError as e:
    return failure(g, "nch db", ~"cannot delete {path}: {e.msg}")
  g.log.log(lvInfo, commandName, leDeleted, fmt"deleted {what}")
  sayDeleted(g, ~"deleted {what}")
  exitOk

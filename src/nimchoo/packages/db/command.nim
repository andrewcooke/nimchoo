## `nch db`: the database file.  With no arguments it says where it is, how big, and what it holds,
## table by table (`holding.nim`); `--delete -f` deletes it, and
## with it the data of every user (the cache, which can be made again, is `nch cache`).  Does nothing without
## -f; on a terminal it then counts down, in the bad style, so there is time to press Ctrl-C (`-f -f`: no countdown).

import std/[options, os, strutils]
import db_connector/db_sqlite
import ../../core/[access, globals, ruled]
import ../util/args/[args, usage]
import ../ui/units
import ../../core/errors
import ../../core/logfile
import ../ui/[live, style]
import ../confirm/confirm
import ./statement
import ./[holding, params, store]

{.push raises: [].}

const commandName* = "db" ## what the user types after `nch`

proc options*(g: Globals): seq[OptDoc] {.nimcall, raises: [].} =
  ## The options of `nch db`, described (for tab completion).
  dbSpec().docs

const
  synopsis = """usage: nch [--db PATH] db
       nch [--db PATH] db --delete -f"""
  intro =
    """Without options, say where the database is and how big, and what it holds, table by table: the package that
owns each, how many rows, how much of the file it takes (with its indexes) and the tables it refers to (who else may
read each: `nch packages --tables`)."""

proc usageText*(width: int): seq[Line] =
  ## The usage: the synopsis, the introduction and the options, wrapped to `width`.
  usageOf(
    synopsisLines(synopsis), proseLines(intro, width), optionLines(dbSpec().docs, width)
  )

proc size(path: string): int64 =
  ## The database file with its journal files.
  for suffix in ["", "-journal", "-wal", "-shm"]:
    try:
      if fileExists(path & suffix):
        result += getFileSize(path & suffix)
    except OSError:
      discard

proc freeSpace(path: string): string =
  ## ", 12 MB free" when a deleted row's space is waiting to be reused or given back; "" if none or unknown.
  try:
    let db = open(path, "", "", "")
    defer:
      db.close()
    let free =
      db.scalar(int64, "pragma freelist_count") * db.scalar(int64, "pragma page_size")
    if free > 0:
      result = ", " & humanBytes(free) & " free"
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
    raiseStore("cannot open " & path & ": " & e.msg)
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
        refers.add span(", ")
      refers.add span(r, "table")
    rows.add @[
      @[span(t.name, "table")],
      (if t.owner.isSome: @[span(t.owner.get, "pkg")] else: plain("-")),
      plain(insertSep($t.rows, ',')),
      plain(humanBytes(t.bytes)),
      (if refers.len == 0: plain("-") else: refers),
    ]
  result = ruled(
    @["table", "owner package", "rows", "size", "refers to"],
    rows,
    width,
    right = {2, 3},
  )
  if h.others > 0:
    result.add plain("")
    result.add plain(
      "and " & $h.others &
        " tables of SQLite and SpatiaLite and the record of the fragments, " &
        humanBytes(h.othersBytes)
    )

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch db ARGS`; returns the exit status.
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    g.showAll osOut, usageText(helpWidth(stdout))
    return exitOk
  of pkProblem:
    return usageError(g, "nch db", usageText(helpWidth(stderr)), parsed.problem)
  of pkOk:
    discard
  let p = parsed.params
  let path = resolveDbPath(g.dbPath)
  if not fileExists(path):
    g.show(osOut, @[span("no database at "), span(path, "file")])
    return exitOk
  if p.action == daShow:
    g.show(
      osOut,
      @[span(path, "file"), span(" (" & humanBytes(size(path)) & freeSpace(path) & ")")],
    )
    g.show(osOut, plain(""))
    try:
      g.showAll(osOut, tablesLines(g, path, helpWidth(stdout)))
    except StoreError as e:
      return failure(g, "nch db", e.msg)
    return exitOk
  let what =
    "the database " & path & " (" & humanBytes(size(path)) &
    ") with the data of every user"
  if p.force == fNo:
    return failure(g, "nch db", "would delete " & what & "; use `-f` to confirm")
  pause(g.theme, what, p.force)
  try:
    for suffix in ["", "-journal", "-wal", "-shm"]:
      removeFile path & suffix
  except OSError as e:
    return failure(
      g, "nch db", @[span("cannot delete "), span(path, "file"), span(": " & e.msg)]
    )
  g.log.log(lvInfo, commandName, leDeleted, "deleted " & what)
  sayDeleted(g, "deleted " & what)
  exitOk

import std/[options, tables, unittest]
import db_connector/db_sqlite
import nimchoo/packages/db/[holding, statement]

proc made(): DbConn =
  ## A small database: two tables of packages (one refers to the other), the shadow table of a spatial index, one of
  ## SpatiaLite's and one that no package owns.
  result = open(":memory:", "", "", "")
  result.execScript(
    """create table a (id integer primary key autoincrement, x);
    create table b (id integer primary key, a_id integer references a(id), y);
    create index b_y on b(y);
    create table idx_a_geom_node (nodeno integer primary key, data);
    create table geometry_columns (f_table_name text);
    create table left_over (z);
    insert into a(x) values (1), (2), (3);
    insert into b(a_id, y) values (1, 'p');"""
  )

let owners = {"a": "pa", "b": "pb"}.toTable

proc ownerOf(t: string): Option[string] {.raises: [].} =
  if t in owners:
    some(owners.getOrDefault(t))
  elif t.len > 4 and t[0 .. 3] == "idx_":
    some("pa")
  else:
    none(string)

suite "db holding: what a database holds":
  test "the tables of the packages, with owner, rows, size and the tables they refer to; one no package owns too":
    let db = made()
    defer:
      db.close()
    let h = holding(db, ownerOf)
    var byName: Table[string, TableHolding]
    for t in h.tables:
      byName[t.name] = t
    check byName.len == 3 # a, b, left_over
    check byName["a"].owner == some("pa") and byName["a"].rows == 3
    check byName["b"].refersTo == @["a"] and byName["b"].rows == 1
    check byName["left_over"].owner.isNone
      # (listed: something left that no package owns)
    check byName["a"].bytes > 0 and byName["b"].bytes > 0

  test "a spatial index is part of its table; SQLite's and SpatiaLite's tables are counted together":
    let db = made()
    defer:
      db.close()
    let h = holding(db, ownerOf)
    for t in h.tables:
      check t.name != "idx_a_geom_node" and t.name != "geometry_columns" and
        t.name != "sqlite_sequence"
    check h.others == 2 # geometry_columns, sqlite_sequence
    check h.othersBytes > 0

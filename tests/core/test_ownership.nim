## Which package owns which table (core/ownership.nim): the scan of the DDL on samples, and on the real
## fragments, compared with what SQLite makes when they are applied one at a time.

import std/[options, os, sequtils, sets, tables, unittest]
import nimchoo/core/ownership
import nimchoo/packages/db/statement
import nimchoo/packages/db/store
import nimchoo/core/errors
from nimchoo/registry import allFragments, allAccess, newAllAccess

func frag(name, sql: string): Fragment =
  Fragment(name: name, sql: sql)

func names(sql: string): seq[string] =
  tableEvents(sql).mapIt(it.name)

suite "the tables a script makes":
  test "tables, virtual tables, if not exists, quoted names, any case":
    check names(
      "CREATE TABLE a (x integer);\ncreate virtual table b using rtree(id, x);\n" &
        "create table if not exists \"c\" (y);\ncreate table main.[d](z) strict;"
    ) == @["a", "b", "c", "d"]

  test "indexes, views, triggers and other statements are not tables":
    check names(
      "create index i on a(x); create unique index j on a(y); create view v as select 1;\n" &
        "create trigger t after insert on a begin select 1; end; select InitSpatialMetadata(0);"
    ).len == 0

  test "comments are not read":
    check names(
      "-- create table nope (x);\n/* create table nor (x); */ create table yes (x);"
    ) == @["yes"]

  test "a rename":
    let e = tableEvents("alter table old rename to new;")
    check e == @[TableEvent(kind: teRename, name: "new", renamed: "old")]

suite "who owns the tables":
  test "a table is owned by the package of the fragment that makes it":
    let owners = tableOwners(
      @[
        frag("a/001-x.sql", "create table t1(x);"),
        frag("b/001-y.sql", "create table t2(x);"),
      ]
    )
    check ownerOf("t1", owners) == some("a")
    check ownerOf("T2", owners) == some("b")
    check ownerOf("t3", owners).isNone

  test "a rename passes ownership to the new name":
    let owners = tableOwners(
      @[
        frag("a/001.sql", "create table t(x);"),
        frag("a/002.sql", "alter table t rename to u;"),
      ]
    )
    check ownerOf("u", owners) == some("a")
    check ownerOf("t", owners).isNone

  test "a spatial index table belongs to the owner of its table, the longest name winning":
    let owners = tableOwners(
      @[
        frag("a/001.sql", "create table activity(x);"),
        frag("b/001.sql", "create table activity_x(x);"),
      ]
    )
    check ownerOf("idx_activity_start", owners) == some("a")
    check ownerOf("idx_activity_start_node", owners) == some("a")
    check ownerOf("idx_activity_x_geom_rowid", owners) == some("b")
    check ownerOf("idx_other_geom", owners).isNone

  test "a table made twice, or a rename of another package's table, is refused":
    expect PackageError:
      discard tableOwners(
        @[
          frag("a/001.sql", "create table t(x);"),
          frag("b/001.sql", "create table t(x);"),
        ]
      )
    expect PackageError:
      discard tableOwners(
        @[
          frag("a/001.sql", "create table t(x);"),
          frag("b/001.sql", "alter table t rename to u;"),
        ]
      )

suite "the tables of nimchoo":
  test "the scan agrees with SQLite, fragment by fragment, and every table has one owner":
    let dir = getTempDir() / "nch-test-ownership"
    createDir dir
    let path = dir / "o.db"
    removeFile path
    let owners = tableOwners(allFragments)
    var known = initHashSet[string]()
    var made = initHashSet[string]() # what SQLite has made by the fragments so far
    # (the database's own fragment, and SpatiaLite's tables, are core's: they are there before the first)
    block:
      let s = openStore(path, @[], "default")
      for t in s.db.query(
        string, "select lower(name) from sqlite_master where type = 'table'"
      ):
        known.incl t
      s.close()
    for i in 1 .. allFragments.len:
      let f = allFragments[i - 1]
      let s = openStore(path, allFragments[0 ..< i], "default", access = allAccess)
      for t in s.db.query(
        string, "select lower(name) from sqlite_master where type = 'table'"
      ):
        if t in known:
          continue
        known.incl t
        let owner = ownerOf(t, owners)
        check owner.isSome # a table the scan cannot place is a table to look at
        if owner.isSome:
          check owner.get == f.ownerName # (made by the fragment that was just applied)
        made.incl t
      s.close()
    for t, owner in owners:
      check t in made
        # (a table the scan found that SQLite did not make would be a mistake in the scan)

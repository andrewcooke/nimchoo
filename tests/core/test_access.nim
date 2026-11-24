## Who may touch which table (core/access.nim): the rule on made-up packages and tables.

import std/[options, strutils, tables, unittest]
import nimchoo/core/access

func rules(): Access =
  newAccess(
    amEnforce,
    {
      "activity": "importer",
      "idx_activity_start_point": "importer",
      "effort": "climbs",
      "user": "db",
    }.toTable,
    {
      "importer": @["db"],
      "climbs": @["db", "importer"],
      "heartrate": @["db", "impOrter"],
      "other": @["db"],
    }.toTable,
    {"effort": @["activity", "sector"], "sector": @["activity"], "note": @["effort"]}.toTable,
  )

suite "access: the rule":
  test "a package may read and write its own tables":
    check rules().refusal("climbs", opRead, "effort").isNone
    check rules().refusal("climbs", opWrite, "effort").isNone
    check rules().refusal("climbs", opDefine, "effort").isNone

  test "it may read the tables of a package it depends on, but not write or define them":
    check rules().refusal("climbs", opRead, "activity").isNone
    check rules().refusal("climbs", opWrite, "activity").isSome
    check rules().refusal("climbs", opDefine, "activity").isSome

  test "it may not read the tables of a package it does not depend on":
    let why = rules().refusal("other", opRead, "effort")
    check why.isSome
    check "'other'" in why.get and "'effort'" in why.get and "'climbs'" in why.get

  test "the tables of db are readable by every package, and writable by db alone":
    check rules().refusal("other", opRead, "user").isNone
    check rules().refusal("other", opWrite, "user").isSome
    check rules().refusal("db", opWrite, "user").isNone

  test "names are compared as Nim compares them":
    check rules().refusal("heartrate", opRead, "activity").isNone
    check rules().refusal("cLimbs", opWrite, "effort").isNone

  test "a spatial index belongs to the owner of its table":
    check rules().refusal("climbs", opRead, "idx_activity_start_node").isNone
    check rules().refusal("climbs", opWrite, "idx_activity_start_node").isSome
    check rules().refusal("other", opRead, "idx_activity_start_point").isSome

  test "tables nobody made by DDL (SQLite's own, SpatiaLite's) are free, and so is code outside the packages":
    check rules().refusal("climbs", opWrite, "sqlite_master").isNone
    check rules().refusal("", opWrite, "activity").isNone

  test "what a cascade does to the tables that refer to a written table is allowed, however far down":
    let a = rules()
    check a.refusal("importer", opWrite, "effort", written = @["activity"]).isNone
    check a.refusal("importer", opRead, "note", written = @["activity"]).isNone
    check a.refusal("importer", opWrite, "effort").isSome
    check a.refusal("importer", opWrite, "effort", written = @["note"]).isSome
      # (a child is not a parent)
    check a.refusal("other", opRead, "idx_effort_geom", written = @["activity"]).isNone

suite "access: pieces written by other packages":
  test "a read is allowed if a package that wrote a piece may make it":
    check rules().refusal("other", opRead, "effort").isSome
    check rules().refusal("other", opRead, "effort", contributors = @["climbs"]).isNone
    check rules()
      .refusal("other", opRead, "effort", contributors = @["importer"]).isSome
      # (a contributor that may not read it either)

  test "a write or a change of definition is the caller's alone":
    check rules().refusal("other", opWrite, "effort", contributors = @["climbs"]).isSome
    check rules()
      .refusal("other", opDefine, "effort", contributors = @["climbs"]).isSome
    check rules()
      .refusal("climbs", opWrite, "activity", contributors = @["importer"]).isSome

  test "the refusal names the packages that wrote pieces":
    let why = rules().refusal("other", opRead, "effort", contributors = @["importer"])
    check "importer" in why.get

  test "the caller counts as itself, whatever the contributors say":
    check rules().refusal("climbs", opRead, "effort", contributors = @["other"]).isNone

suite "access: who may read a table":
  test "the packages that depend on its owner, sorted; every other package for a table of db; none for one no package owns":
    check rules().readersOf("activity") ==
      @["climbs", "heartrate"]
        # (heartrate names it with another case: names are compared as nim compares them)
    check rules().readersOf("effort").len == 0
    check rules().readersOf("user") == @["climbs", "heartrate", "importer", "other"]
    check rules().readersOf("nothing").len == 0

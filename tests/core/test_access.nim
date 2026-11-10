## Who may touch which table (core/access.nim): the rule on made-up packages and tables.

import std/[options, strutils, tables, unittest]
import nimchoo/core/access

func rules(): Access =
  newAccess(
    amEnforce,
    {
      "activity": "importer",
      "idx_activity_start": "importer",
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
    check rules().refusal("climbs", acRead, "effort").isNone
    check rules().refusal("climbs", acWrite, "effort").isNone
    check rules().refusal("climbs", acDefine, "effort").isNone

  test "it may read the tables of a package it depends on, but not write or define them":
    check rules().refusal("climbs", acRead, "activity").isNone
    check rules().refusal("climbs", acWrite, "activity").isSome
    check rules().refusal("climbs", acDefine, "activity").isSome

  test "it may not read the tables of a package it does not depend on":
    let why = rules().refusal("other", acRead, "effort")
    check why.isSome
    check "'other'" in why.get and "'effort'" in why.get and "'climbs'" in why.get

  test "the tables of db are readable by every package, and writable by db alone":
    check rules().refusal("other", acRead, "user").isNone
    check rules().refusal("other", acWrite, "user").isSome
    check rules().refusal("db", acWrite, "user").isNone

  test "names are compared as Nim compares them":
    check rules().refusal("heartrate", acRead, "activity").isNone
    check rules().refusal("cLimbs", acWrite, "effort").isNone

  test "a spatial index belongs to the owner of its table":
    check rules().refusal("climbs", acRead, "idx_activity_start_node").isNone
    check rules().refusal("climbs", acWrite, "idx_activity_start_node").isSome
    check rules().refusal("other", acRead, "idx_activity_start").isSome

  test "tables nobody made by DDL (SQLite's own, SpatiaLite's) are free, and so is code outside the packages":
    check rules().refusal("climbs", acWrite, "sqlite_master").isNone
    check rules().refusal("", acWrite, "activity").isNone

  test "what a cascade does to the tables that refer to a written table is allowed, however far down":
    let a = rules()
    check a.refusal("importer", acWrite, "effort", written = @["activity"]).isNone
    check a.refusal("importer", acRead, "note", written = @["activity"]).isNone
    check a.refusal("importer", acWrite, "effort").isSome
    check a.refusal("importer", acWrite, "effort", written = @["note"]).isSome
      # (a child is not a parent)
    check a.refusal("other", acRead, "idx_effort_geom", written = @["activity"]).isNone

suite "access: pieces written by other packages":
  test "a read is allowed if a package that wrote a piece may make it":
    check rules().refusal("other", acRead, "effort").isSome
    check rules().refusal("other", acRead, "effort", contributors = @["climbs"]).isNone
    check rules()
      .refusal("other", acRead, "effort", contributors = @["importer"]).isSome
      # (a contributor that may not read it either)

  test "a write or a change of definition is the caller's alone":
    check rules().refusal("other", acWrite, "effort", contributors = @["climbs"]).isSome
    check rules()
      .refusal("other", acDefine, "effort", contributors = @["climbs"]).isSome
    check rules()
      .refusal("climbs", acWrite, "activity", contributors = @["importer"]).isSome

  test "the refusal names the packages that wrote pieces":
    let why = rules().refusal("other", acRead, "effort", contributors = @["importer"])
    check "importer" in why.get

  test "the caller counts as itself, whatever the contributors say":
    check rules().refusal("climbs", acRead, "effort", contributors = @["other"]).isNone

## The schema does not depend on the order the packages' fragments are applied in, as long as a package comes after
## those it depends on; and a database made by an older build gets the fragments added since, after those of the
## packages that depend on theirs, and ends up the same (PACKAGES.md, "Fragments with packages").  This is what
## CLAUDE.md asks to be compared by hand before a squash.

import std/[algorithm, os, random, sequtils, sets, strutils, unittest]
import nimchoo/core/[manifest, registry]
import nimchoo/packages/db/[statement, store]
from nimchoo/registry import allAccess, packages

let dir = getTempDir() / "nch-test-orders"

proc schemaRows(s: Store): seq[string] =
  ## Every table, index, trigger and view (with the sql that made it) and the spatial registrations, sorted.
  for r in s.db.query(
    (string, string, string, string),
    "select type, name, tbl_name, coalesce(sql, '') from sqlite_master where name not like 'sqlite_%'",
  ):
    result.add r[0] & "|" & r[1] & "|" & r[2] & "|" & r[3]
  for r in s.db.query(
    (string, string, string),
    "select f_table_name, f_geometry_column, cast(geometry_type as text) from geometry_columns",
  ):
    result.add "geometry|" & r[0] & "|" & r[1] & "|" & r[2]
  result.sort

proc openFresh(fragments: seq[Fragment], name: string): Store =
  createDir(dir)
  let path = dir / name & ".db"
  removeFile(path)
  openStore(path, fragments, access = allAccess)

proc schemaOf(fragments: seq[Fragment], name: string): seq[string] =
  let s = openFresh(fragments, name)
  result = s.schemaRows
  s.close()

proc randomOrder(seed: int): seq[Registered] =
  ## The packages in a valid order of another kind than the registry's: each time any package whose dependencies are
  ## all in is taken, at random.
  var rng = initRand(seed)
  var left = packages
  var have = initHashSet[string]()
  while left.len > 0:
    let ready = left.filterIt(it.package.depends.allIt(it.normalised in have))
    doAssert ready.len > 0
    let pick = ready[rng.rand(ready.high)]
    have.incl pick.name.normalised
    left.keepItIf(it.name != pick.name)
    result.add pick

suite "the schema, whatever the order":
  let baseline = schemaOf(collectFragments(packages), "baseline")

  test "the schema has the tables of the packages":
    check baseline.anyIt(it.startsWith("table|activity|"))
    check baseline.anyIt(it.startsWith("table|effort|"))
    check baseline.anyIt(it.startsWith("table|impulse|"))

  test "other valid orders of the packages give the same schema":
    for seed in 1 .. 6:
      check schemaOf(collectFragments(randomOrder(seed)), "order" & $seed) == baseline

  test "a database made before a package's later fragments gets them after the fragments of the packages that depend on it":
    let all = collectFragments(packages)
    for p in packages:
      if p.package.fragments.len < 2:
        continue
      let later = p.package.fragments[1 ..^ 1].mapIt(it.name)
      let older = all.filterIt(it.name notin later)
      # the older build made the database (first); this one opens it
      openFresh(older, "old-" & p.name).close()
      let s = openStore(dir / "old-" & p.name & ".db", all, access = allAccess)
      let got = s.schemaRows
      s.close()
      check got == baseline

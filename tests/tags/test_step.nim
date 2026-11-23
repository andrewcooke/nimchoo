import std/[options, os, sequtils, strutils, unittest]
import nimchoo/core/ids
import nimchoo/packages/db/statement
import nimchoo/packages/importer/[channel, importer]
import ../support/shims
import nimchoo/packages/tags/[step, tag]
import nimchoo/packages/user/session
import nimchoo/packages/util/bytes/bytes
import nimchoo/packages/fit/load
import nimchoo/packages/util/warnings/warnings
from nimchoo/registry import allFragments, allAccess

const
  profilePath = "../choochoo/data/sdk/Profile.xlsx"
  ride = "../choochoo/data/test/source/personal/2018-08-27-rec.fit"

let p = loadProfile(profilePath)
let dir = getTempDir() / "nch-test-tags-step"

suite "tags: the sport as a tag":
  test "sport:SPORT:SUB-SPORT, or sport:SPORT when the sub-sport says nothing; no sport, no tag":
    check $sportTag("cycling", "road").get == "sport:cycling:road"
    check $sportTag("cycling", "generic").get == "sport:cycling"
    check $sportTag("cycling", "").get == "sport:cycling"
    check $sportTag("open_water", "").get == "sport:open_water"
    check sportTag("", "road").isNone

  test "what a template of the path caught is a tag: key:value, or the value; what cannot be one is said":
    check $labelTag(PathLabel(key: some("bike"), value: "Cotic")).tag.get == "bike:Cotic"
    check $labelTag(PathLabel(key: none(string), value: "commute")).tag.get == "commute"
    let bad = labelTag(PathLabel(key: some("bike"), value: "my bike"))
    check bad.tag.isNone and bad.problem.get.contains("' '")

  test "an import with labels gives their tags too, and warns of one that cannot be a tag":
    removeDir(dir / "labels")
    createDir(dir / "labels")
    let s = openSession(dir / "labels" / "x.db", allFragments, access = allAccess)
    defer:
      s.close()
    var ws: seq[Warning]
    let labels = @[
      PathLabel(key: some("bike"), value: "cotic"),
      PathLabel(key: none(string), value: "a b"),
    ]
    let r = s.importFile(p, "ride.fit", readBytes(ride), ws, @[tagsStep], labels)
    check r.activities == 1
    let a = ActivityId(s.db.scalar(int64, "select id from activity"))
    check "bike:cotic" in s.tagsOf(a).mapIt($it)
    check r.warnings.anyIt(it.kind == wkPathTag)

  test "an import gives a ride its sport as a tag":
    removeDir(dir)
    createDir(dir)
    let s = openSession(dir / "x.db", allFragments, access = allAccess)
    defer:
      s.close()
    var ws: seq[Warning]
    let r = s.importFile(p, "ride.fit", readBytes(ride), ws, @[tagsStep])
    check r.activities == 1
    check r.extras[0].n == 1
    let a = ActivityId(s.db.scalar(int64, "select id from activity"))
    let sport = s.db.scalar(string, "select sport from activity")
    check s.tagsOf(a).mapIt($it).len == 1
    check $s.tagsOf(a)[0] ==
      $sportTag(
        sport, s.db.scalar(string, "select coalesce(sub_sport, '') from activity")
      ).get

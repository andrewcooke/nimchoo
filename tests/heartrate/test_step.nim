import nimchoo/db/statement
import std/[os, tables, unittest]
import ../support/shims
import nimchoo/db/[channel, store]
import nimchoo/heartrate/step
import nimchoo/importer/importer
import nimchoo/fit/time
import nimchoo/packages/util/bytes/bytes
import nimchoo/modules
import nimchoo/profile/load
import nimchoo/packages/util/warnings/warnings
import ../support/fitbuilder

const
  profilePath = "../choochoo/data/sdk/Profile.xlsx"
  ride = "../choochoo/data/test/source/personal/2018-08-27-rec.fit"
  base = 900_000_000

let p = loadProfile(profilePath)
let dir = getTempDir() / "nch-test-heartrate"

proc openDb(name: string): Store =
  createDir(dir)
  let path = dir / name & ".db"
  removeFile(path)
  store.openStore(path, allFragments)

proc imp(s: Store, data: seq[byte], ws: var seq[Warning]): ImportResult =
  s.importFile(p, "x.fit", data, ws, allImportSteps)

# records at base, base+1, base+2 (heart rate 100, none = 255 (invalid), 0), base+3 twice (last wins: 120, 130);
# the third has a position, the rest do not
proc rec(t: int, hr: int): seq[byte] =
  b(0) & le32(t) & b(hr)

let hand = fitFile(
  defn(0, 20, @[(253, 4, uint32T), (3, 1, uint8T)]) & rec(base, 100) & rec(
    base + 1, 255
  ) & rec(base + 2, 0) & rec(base + 3, 120) & rec(base + 3, 130) &
    defn(1, 18, @[(253, 4, uint32T), (2, 4, uint32T), (5, 1, enumT)]) & b(1) &
    le32(base + 3) & le32(base) & b(2)
)

suite "heartrate: the readings of an activity":
  test "rounded, in order; zero and below are no reading":
    var ss: Samples
    ss["heart_rate"] = @[
      Sample(t: UnixTime(1), v: 60),
      Sample(t: UnixTime(2), v: 0),
      Sample(t: UnixTime(3), v: 61.6),
    ]
    check readings(ss) == @[(UnixTime(1), 60), (UnixTime(3), 62)]
    check readings(Samples()).len == 0

suite "heartrate: import":
  test "a hand-built file: invalid and zero readings are dropped, the last of a second kept":
    let s = openDb("hand")
    defer:
      s.close()
    var ws: seq[Warning]
    let r = s.imp(hand, ws)
    check r.activities == 1
    check r.extras.len == 1 and r.extras[0].n == 2
    check s.db.scalar(
      string,
      "select group_concat((t - 1531065600) || ':' || bpm) from (select * from heartrate order by t)",
    ) == "0:100,3:130"

  test "a real ride: a reading for each coordinate":
    let s = openDb("ride")
    defer:
      s.close()
    var ws: seq[Warning]
    let r = s.importFile(p, "ride.fit", readBytes(ride), ws, allImportSteps)
    check r.coords == 2099
    check r.extras[0].n == 2099
    check s.db.scalar(int, "select count(*) from heartrate") == 2099
    check s.db.scalar(string, "select min(bpm) || '-' || max(bpm) from heartrate") ==
      "84-156"
    # they lie in the activity's time range
    check s.db.scalar(
      int,
      """select count(*) from heartrate h join activity a on a.id = h.activity_id
      where h.t < a.start_t or h.t > a.end_t + 1""",
    ) == 0

  test "without the step nothing is written; the table is empty":
    let s = openDb("nostep")
    defer:
      s.close()
    var ws: seq[Warning]
    let r = s.importFile(p, "ride.fit", readBytes(ride), ws)
    check r.extras.len == 0
    check s.db.scalar(int, "select count(*) from heartrate") == 0

  test "a file with no heart rate writes none":
    let s = openDb("none")
    defer:
      s.close()
    let noHr = fitFile(
      defn(1, 18, @[(253, 4, uint32T), (2, 4, uint32T), (5, 1, enumT)]) & b(1) &
        le32(base + 3) & le32(base) & b(2)
    )
    var ws: seq[Warning]
    check s.imp(noHr, ws).extras[0].n == 0

  test "readings go with the activity: deleting it deletes them":
    let s = openDb("cascade")
    defer:
      s.close()
    var ws: seq[Warning]
    discard s.imp(hand, ws)
    s.db.execute("delete from activity")
    check s.db.scalar(int, "select count(*) from heartrate") == 0

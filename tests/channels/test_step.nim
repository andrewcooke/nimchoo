import ../support/arrays
import nimchoo/packages/db/statement
import std/[options, os, random, sets, tables, unittest]
import nimchoo/core/errors
import ../support/shims
import nimchoo/packages/user/session
import nimchoo/packages/importer/channel
import nimchoo/packages/channels/[kinds, series, step, stored]
import nimchoo/packages/importer/importer
import nimchoo/packages/fit/time
import nimchoo/core/ids
import nimchoo/packages/util/bytes/bytes
from nimchoo/registry import allFragments, allAccess, newAllAccess
import nimchoo/packages/fit/load
import nimchoo/packages/util/warnings/warnings
import ../support/fitbuilder

const
  profilePath = "../choochoo/data/sdk/Profile.xlsx"
  ride = "../choochoo/data/test/source/personal/2018-08-27-rec.fit"
  everything =
    "../choochoo/data/test/source/python-fitparse/Edge810-Vector-2013-08-16-15-35-10.fit"
    # an Edge 810 with Vector pedals: every channel
  base = 900_000_000

let p = loadProfile(profilePath)
let dir = getTempDir() / "nch-test-channels"

proc openDb(name: string): Session =
  createDir(dir)
  let path = dir / name & ".db"
  removeFile(path)
  openSession(path, allFragments, access = allAccess)

proc imp(s: Session, data: seq[byte], ws: var seq[Warning]): ImportResult =
  s.importFile(p, "x.fit", data, ws, @[channelsStep])

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

func samples(field: string, values: seq[(int, float)]): Samples =
  for (t, v) in values:
    result.mgetOrPut(field, @[]).add Sample(t: UnixTime(t), v: v)

suite "channels: the list":
  test "each channel's name is its own, it has fields, and its readings fit its packing":
    var names: HashSet[string]
    for ch in ChannelKind:
      let s = specs[ch]
      checkpoint s.name
      check s.name notin names and s.fields.len > 0 and s.step > 0
      names.incl s.name
      check s.lowest <= s.highest
      check s.lowest in s.packing.range and s.highest in s.packing.range
      check channelNamed(s.name) == some(ch)
    check channelNamed("nonesuch").isNone

  test "the import step asks for every field of every channel, once each":
    var all: seq[string]
    for ch in ChannelKind:
      for f in specs[ch].fields:
        if f notin all:
          all.add f
    check channelsStep.channels == all

suite "channels: the readings of an activity":
  test "heart rate: rounded, in order; outside 1 to 254 is no heart rate, and is counted":
    let ss =
      samples("heart_rate", @[(1, 60.0), (2, 0.0), (3, 61.6), (4, 300.0), (5, 254.0)])
    let r = readings(ss, chHeartRate)
    check r.rows ==
      @[(UnixTime(1), 60'i64), (UnixTime(3), 62'i64), (UnixTime(5), 254'i64)]
    check r.dropped == 2
    check readings(Samples(), chHeartRate).rows.len == 0

  test "speed: stored in its steps (mm/s); the first field a second has wins, the other fills in":
    var ss = samples("enhanced_speed", @[(1, 5.0), (3, 7.25)])
    for x in samples("speed", @[(1, 99.0), (2, 6.5)])["speed"]:
      ss.mgetOrPut("speed", @[]).add x
    let r = readings(ss, chSpeed)
    check r.rows ==
      @[(UnixTime(1), 5000'i64), (UnixTime(2), 6500'i64), (UnixTime(3), 7250'i64)]
    check r.dropped == 0
    check value(chSpeed, 7250) == 7.25

  test "a value that is no number, or past the stored range, is dropped and counted":
    let ss = samples("temperature", @[(1, -5.0), (2, NaN), (3, 101.0), (4, 30.0)])
    let r = readings(ss, chTemperature)
    check r.rows == @[(UnixTime(1), -5'i64), (UnixTime(4), 30'i64)]
    check r.dropped == 2
    check readings(samples("cadence", @[(1, 0.0)]), chCadence).rows.len == 1
      # (a cadence of zero is a reading)

  test "every packing gives back what it was given, at both ends of the readings":
    for ch in ChannelKind:
      let s = specs[ch]
      checkpoint s.name
      let rows =
        @[(UnixTime(10), s.lowest), (UnixTime(11), s.highest), (UnixTime(70), s.lowest)]
      let packed = pack(ch, rows)
      check packed.gaps == "\x00\x01\x3B" # (0, 1 and 59 s: a byte each)
      check unpack(ch, packed) == rows

  test "a byte a gap, every second or not; the distance about two bytes a reading at riding speed":
    var hr, dist: seq[(UnixTime, int64)]
    for i in 0 ..< 3600:
      let t = UnixTime(1000 + i + i div 10) # (a second missing every ten)
      hr.add (t, 120'i64)
      dist.add (t, int64(i) * 700) # 7 m a second
    check pack(chHeartRate, hr).gaps.len == 3600
    check pack(chHeartRate, hr).values.len == 3600
    check pack(chDistance, dist).values.len == 2 * 3599 + 1
    check unpack(chDistance, pack(chDistance, dist)) == dist

  test "a distance that goes back is kept as it was":
    let rows =
      @[(UnixTime(1), 500'i64), (UnixTime(2), 499'i64), (UnixTime(3), 1200'i64)]
    check unpack(chDistance, pack(chDistance, rows)) == rows

  test "arrays that do not hold what the count says, or hold what is no reading, are a StoreError":
    var packed = pack(chPower, @[(UnixTime(1), 100'i64)])
    packed.count = 2
    expect StoreError:
      discard unpack(chPower, packed)
    packed.count = 0 # (bytes left over)
    expect StoreError:
      discard unpack(chPower, packed)
    var hr = pack(chHeartRate, @[(UnixTime(1), 100'i64)])
    hr.values = "\x00" # (a heart rate of 0)
    expect StoreError:
      discard unpack(chHeartRate, hr)
    var d = pack(chDistance, @[(UnixTime(1), 100'i64)])
    d.values = "\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x7F" # (a change too large to be one)
    expect StoreError:
      discard unpack(chDistance, d)

  test "random bytes never get past a StoreError":
    var r = initRand(11)
    for ch in ChannelKind:
      for i in 0 ..< 2000:
        var p = Packed(start: UnixTime(r.rand(1_000_000)), count: r.rand(5))
        for k in 0 ..< r.rand(12):
          p.gaps.add char(r.rand(255))
        for k in 0 ..< r.rand(12):
          p.values.add char(r.rand(255))
        try:
          discard unpack(ch, p)
        except StoreError:
          discard

suite "channels: import":
  test "a hand-built file: invalid and zero heart rates are dropped (the zero with a warning), the last of a second kept":
    let s = openDb("hand")
    defer:
      s.close()
    var ws: seq[Warning]
    let r = s.imp(hand, ws)
    check r.activities == 1
    check r.extras.len == 1 and r.extras[0].n == 2
    check r.warnings.len == 1 and r.warnings[0].kind == wkBadReading
    check r.warnings[0].msg == "heart rate: 1 value not from 1 to 254 bpm (dropped)"
    s.db.materialise()
    check s.db.scalar(
      string,
      "select group_concat((t - 1531065600) || ':' || bpm) from (select * from heartrate order by t)",
    ) == "0:100,3:130"

  test "a real ride: a heart rate for each coordinate, and the device's speed and distance":
    let s = openDb("ride")
    defer:
      s.close()
    var ws: seq[Warning]
    let r = s.importFile(p, "ride.fit", readBytes(ride), ws, @[channelsStep])
    check r.coords == 2099
    s.db.materialise()
    check s.db.scalar(int, "select count(*) from heartrate") == 2099
    check s.db.scalar(string, "select min(bpm) || '-' || max(bpm) from heartrate") ==
      "84-156"
    check s.db.scalar(
      string,
      "select group_concat(channel) from (select channel from channel_series order by 1)",
    ) == "distance,heart_rate,speed"
    check r.extras[0].n == s.db.scalar(int, "select count(*) from channels")
    # they lie in the activity's time range
    check s.db.scalar(
      int,
      """select count(*) from channels h join activity a on a.id = h.activity_id
      where h.t < a.start_epoch or h.t > a.end_epoch + 1""",
    ) == 0

  test "a file with every channel has a row for each, read back in the channel's unit":
    let s = openDb("everything")
    defer:
      s.close()
    var ws: seq[Warning]
    discard s.importFile(p, "all.fit", readBytes(everything), ws, @[channelsStep])
    check s.db.scalar(int, "select count(*) from channel_series") ==
      ChannelKind.high.ord + 1
    let id = ActivityId(s.db.scalar(int64, "select id from activity"))
    let d = readChannel(s.db, id, chDistance)
    check d.len > 0 and d[^1][1] > 1000.0 # metres, not centimetres
    for i in 1 ..< d.len:
      check d[i][1] >= d[i - 1][1] # the distance never goes back
    s.db.materialise()
    check s.db.scalar(float, "select max(value) from channels where channel = 'speed'") <
      30.0 # m/s

  test "the stored rows, unpacked, are the readings the step made":
    let s = openDb("series")
    defer:
      s.close()
    var ws: seq[Warning]
    discard s.importFile(p, "ride.fit", readBytes(ride), ws, @[channelsStep])
    let id = ActivityId(s.db.scalar(int64, "select id from activity"))
    s.db.materialise()
    let rows =
      s.db.query(tuple[t, bpm: int64], "select t, bpm from heartrate order by t")
    let decoded = readStored(s.db, id, chHeartRate)
    check decoded.len == rows.len and rows.len == 2099
    for i in 0 ..< rows.len:
      check int64(decoded[i][0]) == rows[i].t and decoded[i][1] == rows[i].bpm
    check readStored(s.db, id, chPower).len == 0 # (a channel it does not have)

  test "without the step nothing is written; the table is empty":
    let s = openDb("nostep")
    defer:
      s.close()
    var ws: seq[Warning]
    let r = s.importFile(p, "ride.fit", readBytes(ride), ws)
    check r.extras.len == 0
    check s.db.scalar(int, "select count(*) from channel_series") == 0

  test "a file with no channels writes none":
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
    check s.db.scalar(int, "select count(*) from channel_series") == 0

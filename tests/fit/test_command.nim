import std/[os, tables, unittest]
import nimchoo/errors
import nimchoo/fit/bytes
import nimchoo/cli/common
import nimchoo/fit/command as fitCommand
import nimchoo/fit/[reader, records]
import nimchoo/profile/default
import nimchoo/profile/load
import nimchoo/fit/tokens
import ../support/fitbuilder

const
  profilePath = "../choochoo/data/sdk/Profile.xlsx"
  activity = "../choochoo/data/test/source/sdk/Activity.fit"

let p = loadProfile(profilePath)

func counts(p: Profile): (int, int, int) =
  var fields = 0
  for m in p.messages.values:
    fields += m.fields.len
  (p.types.len, p.messages.len, fields)

suite "default profile":
  test "the built-in profile is the same as the file":
    check counts(loadDefaultProfile()) == counts(p)
    check counts(defaultProfile().profile) == counts(p)

suite "nch fit rendering":
  test "csv lines look like the SDK's":
    var lines: seq[string]
    var warnings: seq[Warning]
    renderInto(p, readBytes(activity), true, lines, warnings)
    check lines[0] ==
      "Definition,0,file_id,serial_number,1,,time_created,1,," &
      "manufacturer,1,,product,1,,type,1,"
    check lines[1] ==
      "Data,0,file_id,serial_number,\"2147483647\",," &
      "time_created,\"702940946\",,manufacturer,\"15\",,garmin_product,\"1\",," &
      "type,\"4\","
    check warnings.len == 0

  test "text dump names enumerations and formats times":
    let body =
      defn(0, 20, @[(253, 4, uint32T), (3, 1, uint8T)]) &
      defn(1, 21, @[(0, 1, enumT), (1, 1, enumT)]) & b(0) & le32(1000) & b(150) &
      b(1, 0, 0)
    var lines: seq[string]
    var warnings: seq[Warning]
    renderInto(p, fitFile(body), false, lines, warnings)
    check lines ==
      @[
        "record: timestamp=1989-12-31T00:16:40Z  heart_rate=150 bpm",
        "event: event=timer  event_type=start",
      ]

  test "a time field declared wider than 32 bits shows a number that cannot be a time as the number":
    # (the class: corrupt input never reaches a Defect; this was an overflow in fromUnix)
    for (lo, hi, shown) in [
      (0xFFFFFFFE'i64, 0x7FFFFFFF'i64, "9223372036854775806"), # (the largest that is not the marker)
      (0'i64, 0x80000000'i64, "-9223372036854775808"),
      (0xFFFFFFFF'i64, 0'i64, "4294967295"),
    ]:
      let body = defn(0, 20, @[(253, 8, sint64T)]) & b(0) & le32(lo) & le32(hi)
      var lines: seq[string]
      var warnings: seq[Warning]
      renderInto(p, fitFile(body), false, lines, warnings)
      check lines == @["record: timestamp=" & shown]

  test "unknown messages and fields are shown":
    let body = defn(0, 65000, @[(7, 1, uint8T)]) & b(0, 5)
    var lines: seq[string]
    var warnings: seq[Warning]
    renderInto(p, fitFile(body), false, lines, warnings)
    check lines == @["unknown(65000): ?7=5"]

  test "output before an error is kept":
    var data = fitFile(defn(0, 20, @[(3, 1, uint8T)]) & b(0, 1) & b(3, 1))
    var lines: seq[string]
    var warnings: seq[Warning]
    expect FitError:
      renderInto(p, data, true, lines, warnings)
    check lines.len == 2 # the definition and the first record

suite "nch fit command line":
  test "bad usage":
    check fitCommand.run(Globals(), @[]) == 2
    check fitCommand.run(Globals(), @["--bogus", "x.fit"]) == 2
    check fitCommand.run(Globals(), @["--profile"]) == 2
    check fitCommand.run(Globals(), @["a.fit", "b.fit"]) == 2

  test "missing file":
    check fitCommand.run(Globals(), @["/does/not/exist.fit"]) == 1

suite "definition events":
  test "developer fields are named once described":
    let described =
      defn(
        0,
        206,
        @[
          (0, 1, uint8T),
          (1, 1, uint8T),
          (2, 1, uint8T),
          (3, 8, stringT),
          (8, 4, stringT),
        ],
      ) & b(0, 0, 1, 132) & b(112, 111, 119, 101, 114, 0, 0, 0) & b(87, 0, 0, 0)
    let body =
      described & defn(1, 20, @[(3, 1, uint8T)], dev = @[(1, 2, 0), (2, 1, 0)]) &
      b(1, 99) & le16(321) & b(5)
    var r = initReader(p, fitFile(body))
    var defs: seq[Event]
    for ev in r.events(p):
      if ev.kind == evDefinition:
        defs.add ev
    check defs.len == 2
    check defs[0].message == "field_description"
    check defs[1].message == "record"
    check defs[1].local == 1
    check defs[1].fields == @[("heart_rate", 1), ("power", 1), ("", 1)]

suite "nch fit exit codes":
  let dir = getTempDir() / "nch-test-fit"
  createDir(dir)

  test "help is not an error":
    check fitCommand.run(Globals(), @["--help"]) == 0

  test "a profile that is not an xlsx file":
    let bad = dir / "not-a-profile.xlsx"
    writeFile(bad, "this is not an xlsx file")
    check fitCommand.run(Globals(), @["--profile", bad, activity]) == 1
    check fitCommand.run(Globals(), @["--profile=" & bad, activity]) == 1
    removeFile(bad)

  test "a missing profile file":
    check fitCommand.run(Globals(), @["--profile=" & dir / "missing.xlsx", activity]) ==
      1

  test "a corrupt fit file":
    let bad = dir / "bad.fit"
    writeFile(bad, "this is not a fit file at all")
    check fitCommand.run(Globals(), @[bad]) == 1
    removeFile(bad)

  test "a truncated fit file fails, after printing what could be read":
    let data = fitFile(defn(0, 20, @[(3, 4, uint32T)]) & b(0, 1, 2))
    let path = dir / "truncated.fit"
    var s = newString(data.len)
    for i, x in data:
      s[i] = char(x)
    writeFile(path, s)
    check fitCommand.run(Globals(), @[path]) == 1
    removeFile(path)

  test "a good file":
    check fitCommand.run(Globals(), @["--csv", activity]) == 0

## Fuzzing of the profile loader (`loadProfileFromBytes`: the xlsx reader and then the reading of the Types and Messages
## sheets), which reads Profile.xlsx, a file the user can name with `--profile`.  A small profile that uses the sheets'
## columns, and the real Profile.xlsx (fewer rounds: it is 190 KB and takes 30 ms to load), are damaged in their zip
## container and in the xml of each part.  The result must be a profile, a `ProfileError` or an `XlsxError`, never a
## Defect or a long wait.  Fixed seed; a failing input is saved.
##
## NCH_FUZZ_ROUNDS (default 60) scales the length: 20 small profiles per round, one real one per 30 rounds.

import std/[monotimes, os, random, strutils, tables, times, unittest]
import nimchoo/core/errors
import nimchoo/packages/fit/load
import ../support/[fuzzfiles, xlsxbuilder, xlsxmutate]

const
  typesHeader = @["Type Name", "Base Type", "Value Name", "Value", "Comment"]
  messagesHeader = @[
    "Message Name", "Field Def #", "Field Name", "Field Type", "Array", "Components",
    "Scale", "Offset", "Units", "Bits", "Accumulate", "Ref Field Name",
    "Ref Field Value",
  ]

func field(
    num, name, typ: string,
    scale = "",
    offset = "",
    accumulate = "",
    components = "",
    bits = "",
    refName = "",
    refValue = "",
): seq[string] =
  @[
    "", num, name, typ, "", components, scale, offset, "", bits, accumulate, refName,
    refValue,
  ]

func smallProfile(): string =
  ## A profile with a little of everything the loader reads: enums, a date type, scales and offsets, accumulated fields,
  ## components, sub-fields (a reference field and its value).
  let types = @[
    typesHeader,
    @["mesg_num", "enum", "", "", ""],
    @["", "", "file_id", "0", ""],
    @["", "", "record", "20", ""],
    @["sport", "enum", "", "", ""],
    @["", "", "running", "1", ""],
    @["", "", "cycling", "2", ""],
    @["date_time", "uint32", "", "", ""],
    @["", "", "min", "268435456", ""],
  ]
  let messages = @[
    messagesHeader,
    @["record", "", "", "", "", "", "", "", "", "", "", "", ""],
    field("253", "timestamp", "date_time"),
    field("3", "heart_rate", "uint8", scale = "2", offset = "10"),
    field("5", "distance", "uint32", scale = "100", accumulate = "1"),
    field(
      "6", "speed", "uint16", scale = "1000", components = "enhanced_speed", bits = "16"
    ),
    field("73", "enhanced_speed", "uint32", scale = "1000"),
    field("7", "sport", "sport", refName = "heart_rate", refValue = "1"),
    @["file_id", "", "", "", "", "", "", "", "", "", "", "", ""],
    field("0", "type", "sport"),
  ]
  xlsxFile(@[("Types", types), ("Messages", messages)])

proc loads(x: string) {.raises: [ProfileError, XlsxError].} =
  discard loadProfileFromBytes(x)

proc fuzz(
    originals: seq[(string, string)], count: int, seed: int64, target: string
): tuple[stats: string, failures: Table[string, string]] =
  ## Damage the parts `count` times; each result must load or be refused by us, quickly.
  var r = initRand(seed)
  var ok = 0
  for round in 0 ..< count:
    let x = r.damagedXlsx(originals)
    var what = ""
    let started = getMonoTime()
    try:
      loads(x)
      inc ok
    except ProfileError, XlsxError:
      discard
    except Exception as e: # the point of the test: nothing else may be raised
      what = signatureOf(e)
    if what == "" and (getMonoTime() - started).inMilliseconds > 2000:
      what = "took more than 2 s"
    if what != "" and what notin result.failures:
      result.failures[what] = saveFailure(target, target, round, bytesOf(x), ".xlsx")
  result.stats = $count & " profiles, " & $ok & " loaded"

suite "profile fuzzing":
  let rounds = parseInt(getEnv("NCH_FUZZ_ROUNDS", "60"))

  proc report(stats: string, failures: Table[string, string]) =
    checkpoint stats
    if getEnv("NCH_FUZZ_STATS") != "":
      echo stats
    for what, saved in failures:
      checkpoint what & "  (saved: " & saved & ")"
    check failures.len == 0

  test "the small profile that is damaged is good to begin with":
    check loadProfileFromBytes(smallProfile()).messages.len == 2

  test "damaged small profiles load or are refused with an error of ours":
    let (stats, failures) =
      fuzz(partsOf(smallProfile()), rounds * 20, 20261115, "profile")
    report(stats, failures)

  test "damaged copies of the real Profile.xlsx load or are refused with an error of ours":
    let (stats, failures) = fuzz(
      partsOf(readFile("../choochoo/data/sdk/Profile.xlsx")),
      max(2, rounds div 30),
      20261116,
      "realprofile",
    )
    report(stats, failures)

  test "files that once broke the loader load or are refused with an error of ours":
    for target in ["profile", "realprofile"]:
      for path in savedFailures(target, ".xlsx"):
        try:
          loads(readFile(path))
        except ProfileError, XlsxError:
          discard

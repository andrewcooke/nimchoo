## Fuzzing of `decodeBits`, which reads the list of activities from an address (`/map?bits=...`: input from outside):
## random strings, and valid strings damaged.  It must never raise (a Defect), and what it accepts must be a list of
## ids that is in order, within 1..maxId, and that encodes and decodes to itself.  Fixed seed; a failing string is saved.
##
## NCH_FUZZ_ROUNDS (default 60) scales the length: 400 strings per round.

import std/[os, random, sequtils, strformat, strutils, tables, unittest]
import nimchoo/packages/selection/bits
import ../support/fuzzfiles

const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

proc randomIds(r: var Rand, maxId: int64): seq[int64] =
  ## A set of activities of one of the usual shapes.
  case r.rand(4)
  of 0:
    result = @[r.rand(1'i64 .. maxId)]
  of 1:
    let a = r.rand(1'i64 .. maxId)
    result = toSeq(a .. min(maxId, a + r.rand(0 .. 300)))
  of 2:
    for _ in 0 .. r.rand(1 .. 6):
      let a = r.rand(1'i64 .. maxId)
      result.add toSeq(a .. min(maxId, a + r.rand(0 .. 40)))
  of 3:
    for _ in 0 .. r.rand(1 .. 60):
      result.add r.rand(1'i64 .. maxId)
  else:
    result = toSeq(1'i64 .. maxId)

proc damage(r: var Rand, s: string): string =
  ## One to three changes of a string: of its characters, its length, or runs of one character.
  result = s
  for _ in 0 ..< r.rand(1 .. 3):
    let at =
      if result.len == 0:
        0
      else:
        r.rand(result.high)
    case r.rand(8)
    of 0: # another character of the alphabet
      if result.len > 0:
        result[at] = r.sample(alphabet)
    of 1: # any byte at all
      if result.len > 0:
        result[at] = char(r.rand(255))
    of 2: # a bit of a character
      if result.len > 0:
        result[at] = char(ord(result[at]) xor (1 shl r.rand(7)))
    of 3: # cut short
      result.setLen(at)
    of 4: # characters appended
      for _ in 0 ..< r.rand(1 .. 12):
        result.add r.sample(alphabet)
    of 5: # a character removed
      if result.len > 0:
        result.delete(at .. at)
    of 6: # a long run of zero bits (or one) where a number is read
      result.insert(repeat(r.sample("A_"), r.rand(1 .. 20)), at)
    of 7: # a piece copied to another place
      if result.len > 1:
        let a = r.rand(result.high)
        let b = min(result.high, a + r.rand(0 .. 8))
        result.insert(result[a .. b], r.rand(result.len))
    else: # two characters swapped
      if result.len > 1:
        swap(result[at], result[r.rand(result.high)])

proc randomString(r: var Rand): string =
  ## Not derived from a real list.
  for _ in 0 ..< r.rand(0 .. 40):
    result.add(
      if r.rand(5) == 0:
        char(r.rand(255))
      else:
        r.sample(alphabet)
    )

proc problemWith(s: string, maxId: int64): string =
  ## What is wrong with the way `decodeBits` read `s`, if anything ("" if all is well).
  let d = decodeBits(s, maxId)
  if d.problem != "":
    if d.ids.len > 0:
      return "ids as well as a problem"
    return ""
  for i, id in d.ids:
    if id < 1 or id > maxId:
      return "id " & $id & " is outside 1.." & $maxId
    if i > 0 and id <= d.ids[i - 1]:
      return "ids not in order at " & $i
  let again = decodeBits(encodeBits(d.ids), maxId)
  if again.problem != "" or again.ids != d.ids:
    return "the ids do not encode and decode to themselves"

suite "bits fuzzing":
  let rounds = parseInt(getEnv("NCH_FUZZ_ROUNDS", "60"))

  test "damaged and random strings are refused or read as a list in order":
    var r = initRand(20261112)
    var failures: Table[string, string] # what was wrong -> where the string was saved
    var runs, accepted = 0
    for round in 0 ..< rounds * 400:
      let maxId = r.sample([1'i64, 2, 10, 300, 1112, 5000, 100_000])
      let s =
        case r.rand(2)
        of 0:
          r.randomString()
        else:
          r.damage(encodeBits(r.randomIds(maxId)))
      inc runs
      var what = ""
      try:
        what = problemWith(s, maxId)
        if decodeBits(s, maxId).problem == "":
          inc accepted
      except Exception as e: # the point of the test: nothing may be raised
        what = signatureOf(e)
      if what != "" and what notin failures:
        failures[what] =
          saveFailure("bits", "bits", round, bytesOf(fmt"{maxId}\n{s}"), ".txt")
    let stats = $runs & " strings, " & $accepted & " read as a list"
    checkpoint stats
    if getEnv("NCH_FUZZ_STATS") != "":
      echo stats
    for what, saved in failures:
      checkpoint what & "  (saved: " & saved & ")"
    check failures.len == 0
    check accepted > runs div 10
      # (damage that is always refused would test nothing past the checks)

  test "strings that once broke the reader are read without a Defect":
    for path in savedFailures("bits", ".txt"):
      # (the first line is the maxId, the rest the string)
      let text = readFile(path)
      let parts = text.split('\n', 1)
      check problemWith(parts[1], parseBiggestInt(parts[0])) == ""

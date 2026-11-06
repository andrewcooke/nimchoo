## A set of activities as a short string, for an address: `bits=...`.  The activities are numbered by their ids, which only
## grow, so the string means the same until the database is rebuilt (it is made again from the files then: see the check in
## selection.nim, which catches an old address).  Pure.
##
## The string is bits written six to a character in the URL-safe base64 alphabet (A-Z a-z 0-9 - _), no padding.  The first
## bit says which of two forms follows, whichever is shorter:
##
##   runs    (0): a 3-bit parameter k, the number of runs, then for each run of consecutive ids the gap from the end of
##                the one before (from id 1 for the first) and its length less one, all as Exp-Golomb codes of order k
##                (the number of runs, of order 0).  Good for a date range, a sport, "everything", one ride.
##   bitmap  (1): the highest id, then a bit for each id from 1: 1 if it is in.  Good for a scatter of many.
##
## The empty set is the empty string.  A set of 10 single rides among 1,112 is 18 characters; a range or all of them, 5 to 8.
## One ride among 1,112 is 5 characters.  The string comes from an address, so `decodeBits` trusts nothing: it stops at anything wrong and says what.

import std/[algorithm, strutils]

{.push raises: [].}

const
  alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
  maxChars* = 40_000          ## a longer string is refused
  maxRuns* = 100_000          ## more runs than this are refused
  maxK = 7

type Decoded* = object
  ids*: seq[int64]            ## in order, no repeats
  problem*: string            ## "" if it was read; else what is wrong

# --- writing

func binary(x: int64, width = 0): string =
  ## `x` in binary, at least `width` bits wide.
  var v = x
  while v > 0:
    result.add (if (v and 1) == 1: '1' else: '0')
    v = v shr 1
  result.reverse
  while result.len < width: result = "0" & result

func expGolomb(v: int64, k: int): string =
  ## An Exp-Golomb code of order k for v >= 0: leading zeros, then v + 2^k in binary.
  let x = v + (1'i64 shl k)
  let b = binary(x)
  repeat('0', b.len - 1 - k) & b

func runsOf(ids: seq[int64]): seq[(int64, int64)] =
  ## (start, length) of each run of consecutive ids; `ids` is sorted without repeats.
  for id in ids:
    if result.len > 0 and id == result[^1][0] + result[^1][1]: inc result[^1][1]
    else: result.add (id, 1'i64)

func runsForm(runs: seq[(int64, int64)]): string =
  ## The shortest runs form, over the parameter k.
  for k in 0 .. maxK:
    var bits = "0" & binary(k, 3) & expGolomb(int64(runs.len), 0)
    var prev = 1'i64
    for (start, len) in runs:
      bits.add expGolomb(start - prev, k) & expGolomb(len - 1, k)
      prev = start + len
    if result.len == 0 or bits.len < result.len: result = bits

func bitmapForm(ids: seq[int64]): string =
  let last = ids[^1]
  result = "1" & expGolomb(last, 0)
  var map = repeat('0', int(last))
  for id in ids: map[int(id - 1)] = '1'
  result.add map

func toChars(bits: string): string =
  var padded = bits
  while padded.len mod 6 != 0: padded.add '0'
  for i in countup(0, padded.high, 6):
    var v = 0
    for j in 0 ..< 6: v = v * 2 + (if padded[i + j] == '1': 1 else: 0)
    result.add alphabet[v]

func encodeBits*(ids: openArray[int64]): string =
  ## The string for a set of activity ids (any order; repeats and numbers below 1 are ignored).
  var sorted: seq[int64]
  for id in ids:
    if id >= 1: sorted.add id
  sorted.sort
  var unique: seq[int64]
  for id in sorted:
    if unique.len == 0 or id != unique[^1]: unique.add id
  if unique.len == 0: return ""
  let runs = runsForm(runsOf(unique))
  if unique[^1] > 4 * maxChars: return toChars(runs)       # (a bitmap that long would be refused)
  let map = bitmapForm(unique)
  toChars(if map.len < runs.len: map else: runs)

# --- reading

func decodeBits*(s: string, maxId: int64): Decoded =
  ## The ids in the string.  `maxId` is the highest id that can be (the highest activity id): an id beyond it, a string
  ## that is too long, bad characters, too many runs, bits that run out, or anything left over is a `problem`.
  if s.len == 0: return
  if s.len > maxChars: return Decoded(problem: "the activities are too many to read (" & $s.len & " characters)")
  var bits = newStringOfCap(s.len * 6)
  for c in s:
    let v = alphabet.find(c)
    if v < 0: return Decoded(problem: "'" & $c & "' cannot be in a list of activities")
    bits.add binary(v, 6)
  var pos = 0
  var problem = ""
  proc fail(why: string) =
    if problem.len == 0: problem = why
  proc take(n: int): int64 =
    if pos + n > bits.len:
      fail("the list of activities ends too soon")
      return 0
    for i in 0 ..< n: result = result * 2 + (if bits[pos + i] == '1': 1 else: 0)
    pos += n
  proc golomb(k: int): int64 =
    var zeros = 0
    while pos < bits.len and bits[pos] == '0':
      inc zeros
      inc pos
      if zeros > 40:
        fail("a number in the list of activities is too long")
        return 0
    if pos >= bits.len:
      fail("the list of activities ends too soon")
      return 0
    result = take(zeros + k + 1) - (1'i64 shl k)
  let form = take(1)
  var ids: seq[int64]
  if problem.len == 0 and form == 0:
    let k = int(take(3))
    let count = golomb(0)
    if problem.len == 0 and count > maxRuns: fail("too many runs of activities")
    var prev = 1'i64
    var n = 0'i64
    while problem.len == 0 and n < count:
      let start = prev + golomb(k)
      let len = golomb(k) + 1
      if problem.len > 0: break
      if start < 1 or len < 1 or start + len - 1 > maxId:
        fail("an activity in the list is beyond the last one")
        break
      for id in start ..< start + len: ids.add id
      prev = start + len
      inc n
  elif problem.len == 0:
    let last = golomb(0)
    if problem.len == 0 and (last < 1 or last > maxId): fail("an activity in the list is beyond the last one")
    var id = 1'i64
    while problem.len == 0 and id <= last:
      if take(1) == 1: ids.add id
      inc id
  if problem.len == 0:
    # what is left must be the padding of the last character: under six zeros
    if bits.len - pos >= 6 or bits[pos ..< bits.len].contains('1'):
      fail("there is more in the list of activities than it says")
  if problem.len > 0: return Decoded(problem: problem)
  Decoded(ids: ids)

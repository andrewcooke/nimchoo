## Fuzzing of the server's request checks (`parseTarget`, `route`, `withoutParam`, `hostAllowed`, `cookieValue`,
## `sameToken`), which decide what a web page in the browser can make the server do: addresses and headers that are valid
## are damaged, and random ones made.  Nothing may raise; and what comes out must be safe to use where the server uses it:
## the address of a redirect (it goes into the `Location` header and the log) has no control characters and reads back
## as the same path and query, and a route holds only the arguments of the command's own rules.  Fixed seed; a
## failing address is saved.
##
## NCH_FUZZ_ROUNDS (default 60) scales the length: 400 addresses per round.

import std/[options, os, random, strformat, strutils, tables, unittest]
import nimchoo/packages/ff/web
import nimchoo/packages/map/web as mapWeb
import nimchoo/packages/web/request
import ../support/[fuzzcheck, fuzzfiles, fuzzsamples, textmutate]
let pages = @[mapPage("map"), ffPage("ff")]

const pieces = [
  "%", "%0", "%00", "%0a", "%0d%0a", "%0D", "%2f", "%2F", "%2e%2e", "%25", "%zz", "%7f",
  "%3f", "%23", "%26", "%3d", "+", "#", "?", "&", "=", "&&", "??", "/", "//", "\\",
  "..", "/../", "-", "--", "--worker", "-h", "\x00", "\xff", "%ff", "%c0%af",
  "%e2%80%ae", ":", "@", "http://x",
]

proc damageTarget(r: var Rand, s: string): string =
  ## The text damaged as text, with the pieces that mean something in an address put in.
  result = s
  for _ in 0 ..< r.rand(1 .. 3):
    let at = r.rand(result.len)
    if r.rand(2) == 0:
      result.insert(r.sample(pieces), at)
    else:
      result = r.damageText(result)

proc randomTarget(r: var Rand): string =
  for _ in 0 ..< r.rand(0 .. 40):
    result.add(
      if r.rand(3) == 0:
        r.sample(pieces)
      else:
        $char(r.rand(32 .. 126))
    )

suite "web request fuzzing":
  let rounds = parseInt(getEnv("NCH_FUZZ_ROUNDS", "60"))

  test "damaged and random addresses are refused or safe":
    var r = initRand(20261117)
    var failures: Table[string, string] # what was wrong -> where the address was saved
    var runs, accepted, routed = 0
    for round in 0 ..< rounds * 400:
      let raw =
        if r.rand(3) == 0:
          r.randomTarget()
        else:
          r.damageTarget(r.sample(requestAddresses))
      inc runs
      var what = ""
      try:
        what = requestProblem(raw, pages)
        let t = parseTarget(raw)
        if t.isSome:
          inc accepted
          if route(t.get, pages).isSome:
            inc routed
      except Exception as e: # the point of the test: nothing may be raised
        what = signatureOf(e)
      if what != "" and what notin failures:
        failures[what] = saveFailure("request", "request", round, bytesOf(raw), ".txt")
    let stats = fmt"{runs} addresses, {accepted} read, {routed} routed"
    checkpoint stats
    if getEnv("NCH_FUZZ_STATS") != "":
      echo stats
    for what, saved in failures:
      checkpoint fmt"{what}  (saved: {saved})"
    check failures.len == 0
    check routed > runs div 100
      # (damage that is always refused would test nothing past the checks)

  test "damaged headers are refused or read as they are":
    var r = initRand(20261118)
    for round in 0 ..< rounds * 400:
      let host =
        r.damageTarget(r.sample(["127.0.0.1:62466", "localhost:62466", "LocalHost:1"]))
      let port = r.sample([1, 62466, 0, 65535])
      if hostAllowed(host, port):
        check host.toLowerAscii in [fmt"127.0.0.1:{port}", fmt"localhost:{port}"]
      let cookie =
        r.damageTarget(r.sample(["nch=abc", "a=1; nch=abc; b=2", "xnch=abc", ""]))
      let value = cookieValue(cookie, "nch")
      if value != "":
        check fmt"nch={value}" in cookie
        check ';' notin value
      let a = r.randomTarget()
      let b =
        if r.rand(1) == 0:
          a
        else:
          r.damageTarget(a)
      check sameToken(a, b) == (a == b and a.len > 0)

  test "addresses that once broke the checks are refused or safe":
    for path in savedFailures("request", ".txt"):
      check requestProblem(readFile(path), pages) == ""

## Completing the names of landmarks (src/nimchoo/packages/names/completion.nim).

import std/unittest
import nimchoo/packages/db/statement
import nimchoo/packages/names/completion
import nimchoo/packages/user/session
import ../support/completiondb

suite "completing landmarks":
  test "the landmarks whose names start with what is typed, in order":
    let s = freshDb("landmarks")
    for name in ["Cerro Foo", "cerro bar", "Mirador"]:
      s.db.execute(
        "insert into landmark(name, lon, lat, radius_m) values (:name, 1, 1, 1)",
        name = name,
      )
    let g = s.completing()
    s.close()
    check completeLandmarks(g, "") == @["cerro bar", "Cerro Foo", "Mirador"]
    check completeLandmarks(g, "cerro f") == @["Cerro Foo"]
    check completeLandmarks(g, "x") == newSeq[string]()

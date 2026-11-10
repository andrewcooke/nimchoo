## Completing the names of models (src/nimchoo/packages/model/completion.nim).

import std/unittest
import nimchoo/packages/model/completion
import nimchoo/packages/user/session
import ../support/completiondb

suite "completing models":
  test "the model every database starts with, and only what starts with what is typed":
    let s = freshDb("models")
    let g = s.completing()
    s.close()
    check completeModels(g, "") == @["default"]
    check completeModels(g, "DEF") == @["default"]
    check completeModels(g, "x") == newSeq[string]()

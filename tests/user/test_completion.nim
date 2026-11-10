## Completing the names of users (src/nimchoo/packages/user/completion.nim).

import std/[os, unittest]
import nimchoo/core/errors
import nimchoo/packages/user/[completion, session, users]
import ../support/completiondb

suite "completing users":
  test "the users whose names start with what is typed, whatever the case, in order":
    let s = freshDb("users")
    s.addUser("Bob")
    s.addUser("alice")
    s.addUser("Álvaro")
    let g = s.completing()
    s.close()
    check completeUsers(g, "") == @["alice", "Álvaro", "Bob", "default"]
    check completeUsers(g, "b") == @["Bob"]
    check completeUsers(g, "AL") == @["alice", "Álvaro"] # (accents do not matter)
    check completeUsers(g, "alv") == @["Álvaro"]
    check completeUsers(g, "zz") == newSeq[string]()

  test "what is typed is a value, not SQL or a pattern":
    let s = freshDb("users-quote")
    s.addUser("100%")
    s.addUser("o'brien")
    let g = s.completing()
    s.close()
    check completeUsers(g, "'") == newSeq[string]()
    check completeUsers(g, "o'") == @["o'brien"]
    check completeUsers(g, "100%") == @["100%"]
    check completeUsers(g, "%") == newSeq[string]()
    check completeUsers(g, "_") == newSeq[string]()

  test "nothing is changed: the database is not written, and a missing one is not made":
    let s = freshDb("users-ro")
    let g = s.completing()
    s.close()
    discard completeUsers(g, "")
    var missing = g
    missing.dbPath = g.dbPath & ".missing"
    expect StoreError:
      discard completeUsers(missing, "")
    check not fileExists(missing.dbPath)

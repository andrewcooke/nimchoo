## Completing climbs by name (src/nimchoo/packages/climbs/completion.nim).

import std/unittest
import nimchoo/packages/db/statement
import nimchoo/packages/climbs/completion
import nimchoo/packages/user/session
import ../support/completiondb

proc addSector(s: Session, name: string, n = 1) =
  ## A climb with this name; `n` is its kept number (given when the climb is named: a second of the name is 2).
  s.db.execute(
    "insert into sector(length_m, gain_m, gradient, name, name_n) values (1000, 100, 5, :name, :n)",
    name = name,
    n = n,
  )

suite "completing climbs":
  test "whole names, as shown: a name that is shared carries its kept number":
    let s = freshDb("climbs")
    s.addSector("Farellones")
    s.addSector("Farellones", 2)
    s.addSector("Cerro San Luis")
    s.addSector("Álamo")
    let g = s.completing()
    s.close()
    check completeClimbNames(g, "") ==
      @["Álamo", "Cerro San Luis", "Farellones₁", "Farellones₂"]
    check completeClimbNames(g, "far") == @["Farellones₁", "Farellones₂"]
    check completeClimbNames(g, "Cerro Sa") == @["Cerro San Luis"]
    check completeClimbNames(g, "alamo") == @["Álamo"]

  test "words of the names, for the option that takes text":
    let s = freshDb("climb-words")
    s.addSector("Farellones")
    s.addSector("Farellones", 2)
    s.addSector("Cerro San Luis")
    let g = s.completing()
    s.close()
    check completeClimbWords(g, "") ==
      @["Cerro", "Farellones₁", "Farellones₂", "Luis", "San"]
    check completeClimbWords(g, "s") == @["San"]
    check completeClimbWords(g, "l") == @["Luis"]
    check completeClimbWords(g, "x") == newSeq[string]()

  test "a climb with no name yet is offered as it is shown":
    let s = freshDb("climbs-unnamed")
    s.db.execute("insert into sector(length_m, gain_m, gradient) values (1000, 100, 5)")
    let g = s.completing()
    s.close()
    check completeClimbNames(g, "") == @["unnamed"]

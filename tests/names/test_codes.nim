import std/unittest
import nimchoo/packages/names/codes

suite "GeoNames codes the naming rules share":
  test "abandoned, destroyed and historical places are inactive; others are not":
    for c in ["PPLQ", "PPLW", "PPLH"]:
      check c.isInactivePlace
    for c in ["PPL", "PPLX", "PASS"]:
      check not c.isInactivePlace

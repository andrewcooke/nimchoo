{.push warning[UnreachableCode]: off.} # (`expect` around procedures that never return)
import std/[options, sets, strutils, unittest]
import nimchoo/core/errors
import nimchoo/packages/fit/header
import nimchoo/packages/fit/load
import nimchoo/packages/fit/tokens
import nimchoo/packages/util/xlsx/xlsx
import ../support/fitbuilder

suite "errors":
  test "all our errors are NchError":
    expect NchError:
      raiseFit("x")
    expect NchError:
      raiseProfile("x")
    expect NchError:
      raiseXlsx("x")
    expect NchError:
      discard openWorkbook("this is not a zip file")
    expect NchError:
      discard readHeader(b(12, 16))

  test "FitError without and with an offset":
    try:
      raiseFit("plain")
    except FitError as e:
      check e.offset.isNone
      check e.msg == "plain"
    try:
      raiseFit(12, "bad")
    except FitError as e:
      check e.offset == some(12)
      check e.msg == "bad (at offset 12)"

  test "the tokenizer reports the offset as a field":
    var t = initTokenizer(fitFile(b(0x03, 1)), initHashSet[(int, int)]())
    try:
      for tok in t.tokens:
        discard
      check false # a FitError was expected
    except FitError as e:
      check e.offset == some(12) # just after the 12 byte header
      check "no definition" in e.msg

  test "ProfileError carries the sheet and row":
    try:
      raiseProfile("bad", "Types", 7)
    except ProfileError as e:
      check e.sheet == some("Types")
      check e.row == some(7)

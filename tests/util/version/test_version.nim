import std/[strutils, unittest]
import nimchoo/packages/util/version/version

suite "version":
  test "the number is the one in the nimble file":
    check versionFromNimble("# Package\n\nversion       = \"1.2.3\"\nauthor = \"x\"\n") ==
      "1.2.3"
    check versionFromNimble("author = \"x\"\n") == "unknown"
    check versionFromNimble("") == "unknown"
    check versionFromNimble("version = ") == "unknown"
  test "the commit, clean, dirty, or not known":
    check commitText("a1b2c3d", false) == "a1b2c3d"
    check commitText("a1b2c3d", true) == "a1b2c3d-dirty"
    check commitText("", false) == "unknown"
    check commitText("", true) == "unknown"
  test "the line":
    check versionLine("0.1.0", "a1b2c3d") == "nch 0.1.0 (a1b2c3d)"
  test "this build has a number and a commit":
    check nchVersion.count('.') == 2
    check versionString.startsWith("nch " & nchVersion & " (")
    check nchCommit.len > 0

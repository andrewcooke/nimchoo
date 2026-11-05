import std/[options, os, strutils, tables, times, unittest]
import nimchoo/bundle/unpack
import ../support/env
import nimchoo/cache
import nimchoo/hashing

let dir = getTempDir() / "nch-test-bundle"

proc fresh(name: string): string =
  removeDir(dir / name)
  createDir(dir / name)
  dir / name

func bundle(data: string, name = "Profile.xlsx"): Bundle = Bundle(name: name, data: data)

suite "bundle: what to do about a file":
  let h1 = sha256Hex("one")
  let h2 = sha256Hex("two")
  let h3 = sha256Hex("three")
  test "missing: unpack":
    check decide(none string, none string, h1) == acUnpack
    check decide(none string, some h2, h1) == acUnpack
  test "the file is the program's own: nothing to do, whatever the manifest says":
    check decide(some h1, some h1, h1) == acCurrent
    check decide(some h1, none string, h1) == acCurrent
    check decide(some h1, some h2, h1) == acCurrent
  test "as it was unpacked, but the program has another: replace it":
    check decide(some h2, some h2, h1) == acRefresh
  test "anything else was put there by the author":
    check decide(some h3, some h2, h1) == acCustom        # changed since it was unpacked
    check decide(some h3, none string, h1) == acCustom    # nothing is known about it

suite "bundle: the manifest":
  test "written sorted, read back":
    var m = initTable[string, string]()
    m["b.txt"] = sha256Hex("b")
    m["a.txt"] = sha256Hex("a")
    let text = formatManifest(m)
    check text.splitLines[0].endsWith("  a.txt") and text.splitLines[1].endsWith("  b.txt")
    check parseManifest(text) == m
  test "lines that are not entries are left out":
    check parseManifest("junk\n\nshort  x\n" & sha256Hex("a") & "  a.txt\n") ==
      {"a.txt": sha256Hex("a")}.toTable
    check parseManifest("").len == 0

suite "bundle: resolving a file":
  test "the licence notice is unpacked with anything else":
    let top = fresh("withnotice")
    discard resolve(top, bundle("v1"))
    check readFile(systemDir(top) / "NOTICE") == noticeBundle.data
    check parseManifest(readFile(top / manifestName)).hasKey("NOTICE")
    removeFile(systemDir(top) / "NOTICE")
    discard resolve(top, bundle("v1"))                       # (nothing to unpack: the notice is not brought back)
    check not fileExists(systemDir(top) / "NOTICE")
    discard resolve(top, bundle("v2"))                       # (something is unpacked: it is)
    check fileExists(systemDir(top) / "NOTICE")
  test "the first time it is unpacked and recorded":
    let top = fresh("first")
    let r = resolve(top, bundle("v1"))
    check r.data == "v1" and r.source == soUnpacked
    check r.path == systemDir(top) / "Profile.xlsx" and readFile(r.path) == "v1"
    check parseManifest(readFile(top / manifestName))["Profile.xlsx"] == sha256Hex("v1")
  test "again: the same, nothing rewritten":
    let top = fresh("again")
    discard resolve(top, bundle("v1"))
    let old = fromUnix(1_000_000_000)                       # (a time long ago, set by hand: no waiting)
    setLastModificationTime(systemDir(top) / "Profile.xlsx", old)
    check resolve(top, bundle("v1")).source == soUnpacked
    check getLastModificationTime(systemDir(top) / "Profile.xlsx") == old     # (not written again)
  test "a file that was deleted is unpacked again":
    let top = fresh("deleted")
    discard resolve(top, bundle("v1"))
    removeDir systemDir(top)
    check resolve(top, bundle("v1")).source == soUnpacked
    check readFile(systemDir(top) / "Profile.xlsx") == "v1"
  test "the author's file is used as it is, and never overwritten":
    let top = fresh("custom")
    discard resolve(top, bundle("v1"))
    writeFile(systemDir(top) / "Profile.xlsx", "mine")
    let r = resolve(top, bundle("v1"))
    check r.source == soCustom and r.data == "mine" and r.path == systemDir(top) / "Profile.xlsx"
    # ... even when the program has a newer one
    check resolve(top, bundle("v2")).data == "mine"
    check readFile(systemDir(top) / "Profile.xlsx") == "mine"
    # ... and putting the program's own back makes it the program's again
    writeFile(systemDir(top) / "Profile.xlsx", "v2")
    check resolve(top, bundle("v2")).source == soUnpacked
  test "an untouched file is replaced by a newer one in the program":
    let top = fresh("refresh")
    discard resolve(top, bundle("v1"))
    let r = resolve(top, bundle("v2"))
    check r.data == "v2" and r.source == soUnpacked and readFile(r.path) == "v2"
    check parseManifest(readFile(top / manifestName))["Profile.xlsx"] == sha256Hex("v2")
  test "a file with nothing recorded about it is the author's, unless it is the program's own":
    let top = fresh("unrecorded")
    createDir systemDir(top)
    writeFile(systemDir(top) / "Profile.xlsx", "mine")
    check resolve(top, bundle("v1")).source == soCustom
    writeFile(systemDir(top) / "Profile.xlsx", "v1")
    check resolve(top, bundle("v1")).source == soUnpacked
    check parseManifest(readFile(top / manifestName))["Profile.xlsx"] == sha256Hex("v1")      # (and it is recorded)
  test "several files, each its own":
    let top = fresh("several")
    discard resolve(top, bundle("p1", "Profile.xlsx"))
    discard resolve(top, bundle("c1", "cities.tsv.gz"))
    writeFile(systemDir(top) / "cities.tsv.gz", "my cities")
    check resolve(top, bundle("p2", "Profile.xlsx")).data == "p2"
    check resolve(top, bundle("c2", "cities.tsv.gz")).data == "my cities"
    check parseManifest(readFile(top / manifestName)).len == 3        # (and the notice)
  test "no cache directory, or one that cannot be used: the program's copy":
    check resolve("", bundle("v1")) == Resolved(data: "v1", source: soBundled, path: "", hash: sha256Hex("v1"))
    let top = fresh("unusable")
    writeFile(top / "system", "a file where the directory should be")
    let r = resolve(top, bundle("v1"))
    check r.data == "v1" and r.source == soBundled

# the real files, through the cache directory of the environment (tests/support/env.nim sets one)
import nimchoo/profile/[default, load]

suite "bundle: the profile and the notice":
  setup:
    let top = fresh("real")
    putEnv("NCH_CACHE", top)
  teardown:
    useTestCache()
  test "the default profile is unpacked, and is the built-in one":
    let d = defaultProfile()
    check d.note == ""
    check fileExists(systemDir(top) / "Profile.xlsx")
    check readFile(systemDir(top) / "Profile.xlsx") == readFile("data/Profile.xlsx")
    check parseManifest(readFile(top / manifestName))["Profile.xlsx"] == sha256Hex(readFile("data/Profile.xlsx"))
  test "the author's profile is used, with a note; one that cannot be read is not, with a note":
    discard defaultProfile()
    # a good one: the same spreadsheet with a byte on the end, which readers of zip files allow
    writeFile(systemDir(top) / "Profile.xlsx", readFile("data/Profile.xlsx") & "\0")
    let mine = defaultProfile()
    check mine.note.startsWith("using the profile ") and mine.note.endsWith("(not the built-in one)")
    # a bad one: the built-in is used instead
    writeFile(systemDir(top) / "Profile.xlsx", "this is not a spreadsheet")
    let bad = defaultProfile()
    check bad.note.contains("cannot be used") and bad.note.contains("using the built-in one")
    check bad.profile.messages.len > 0
    expect NchError: discard loadDefaultProfile()                  # (the other one says so as an error)
  test "NOTICE is unpacked and recorded":
    unpackNotice(top)
    check readFile(systemDir(top) / "NOTICE") == readFile("NOTICE")
    check parseManifest(readFile(top / manifestName)).hasKey("NOTICE")
    check noticeBundle.data == readFile("NOTICE")

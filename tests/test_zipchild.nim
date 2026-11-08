import std/[monotimes, os, strutils, tables, times, unittest]
import nimchoo/[zipbytes, zipchild]
import ./support/zips

const exe = "./nch-test" ## the program (built by `nimble test`), run as the child

proc inflater(): Inflater =
  inflateInChild(absolutePath(exe), 60_000)

suite "zip entries inflated in a child":
  test "an entry comes out as it went in":
    let text = repeat("hello, zip. ", 50_000)
    let z = makeZip([("a.txt", text), ("b.txt", "b")])
    check readEntry(z, "a.txt", maxEntrySize, inflater()) == text
    check readEntry(z, "b.txt", maxEntrySize, inflater()) == "b"
  test "more than the limit, whatever the header says, is refused":
    let z = makeZip([("big.txt", repeat("x", 3_000_000))])
    var es = listEntries(z)
    var lying = es["big.txt"]
    lying.size = 100 # (the header says it is small)
    expect ZipError:
      discard extractEntry(z, lying, 1_000_000, inflater())
    let honest = es["big.txt"]
    expect ZipError:
      discard extractEntry(z, honest, 1_000_000, inflater())
  test "a runaway entry ends the child, not the caller":
    # 1.5 GB of zeros deflate to about 1.5 MB; the limit is 1 MB, so the ceiling (3 MB and a little) is passed
    let z = makeZip([("bomb.txt", repeat('\0', 150_000_000))])
    var es = listEntries(z)
    var lying = es["bomb.txt"]
    lying.size = 1000
    let t0 = getMonoTime()
    var said = ""
    try:
      discard extractEntry(z, lying, 1_000_000, inflater())
    except ZipError as e:
      said = e.msg
    check said.contains("too large")
    check (getMonoTime() - t0).inMilliseconds < 30_000
  test "bytes that are not deflate are refused, not trusted":
    let z = makeZip([("a.txt", "hello")])
    var es = listEntries(z)
    var e = es["a.txt"]
    var bad = z
    for i in 30 + 5 ..< min(bad.len, 30 + 5 + 4):
      bad[i] = char(0xff)
    expect ZipError:
      discard extractEntry(bad, e, maxEntrySize, inflater())
  test "a program that is not there is said":
    let z = makeZip([("a.txt", "hello")])
    expect ZipError:
      discard readEntry(z, "a.txt", maxEntrySize, inflateInChild("/nonexistent/nch"))
  test "the child's usage":
    check inflateChildMain(@[]) != 0
    check inflateChildMain(@["a", "b", "x"]) != 0

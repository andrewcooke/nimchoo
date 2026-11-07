import std/[strutils, tables, unittest]
import nimchoo/zipbytes
import ./support/zips

suite "zip files in memory":
  test "the entries of a zip, deflated or stored":
    for deflate in [true, false]:
      let z = makeZip([("a.txt", "hello"), ("dir/b.txt", repeat("x", 5000))], deflate)
      let es = listEntries(z)
      check es.len == 2
      check es.hasKey("a.txt") and es.hasKey("dir/b.txt")
      check extractEntry(z, es["a.txt"]) == "hello"
      check extractEntry(z, es["dir/b.txt"]) == repeat("x", 5000)
      check es["a.txt"].size == 5

  test "bytes that are not a zip, or a zip cut short":
    expect ZipError:
      discard listEntries("this is not a zip file at all, not even close to one")
    expect ZipError:
      discard listEntries("")
    let z = makeZip([("a.txt", "hello")])
    expect ZipError:
      discard listEntries(z[0 ..< z.len - 10]) # the end record is gone
    let es = listEntries(z)
    expect ZipError:
      discard extractEntry(z[0 ..< 20], es["a.txt"]) # the data are gone

  test "an entry with the wrong size, or a compression we cannot do":
    let z = makeZip([("a.txt", "hello")], deflate = false)
    var es = listEntries(z)
    var bad = es["a.txt"]
    bad.size = 99
    expect ZipError:
      discard extractEntry(z, bad)
    bad = es["a.txt"]
    bad.compression = 12
    expect ZipError:
      discard extractEntry(z, bad)
    bad = es["a.txt"]
    bad.size = 300 * 1024 * 1024
    expect ZipError:
      discard extractEntry(z, bad)

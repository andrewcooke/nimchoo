import std/[os, strutils, unittest]
import nimchoo/atomic

let dir = getTempDir() / "nch-test-atomic"

proc leftovers(d: string): seq[string] =
  for f in walkFiles(d / "*"):
    if f.endsWith(".part"):
      result.add f

type Job = tuple[path: string, tag: char, times: int]

proc writer(j: Job) {.thread.} =
  for _ in 1 .. j.times:
    try:
      writeAtomic(j.path, repeat(j.tag, 200_000))
    except CatchableError:
      discard # (the test looks at what a reader sees)

suite "atomic writes":
  test "a file is written whole, with its directory made, and no part file is left":
    removeDir(dir)
    let path = dir / "a" / "b.txt"
    writeAtomic(path, "one")
    check readFile(path) == "one"
    writeAtomic(path, "two")
    check readFile(path) == "two"
    check leftovers(dir / "a").len == 0
  test "writers of one file at the same time: a reader sees one of the texts whole, never a mixture or nothing":
    removeDir(dir)
    let path = dir / "busy.txt"
    writeAtomic(path, repeat('a', 200_000))
    var threads: array[4, Thread[Job]]
    for i in 0 ..< threads.len:
      createThread(threads[i], writer, (path, char(ord('a') + i), 60))
    var seen = 0
    while true:
      var running = false
      for t in threads.mitems:
        if t.running:
          running = true
      let text = readFile(path)
      check text.len == 200_000 and text == repeat(text[0], 200_000)
      inc seen
      if not running:
        break
    joinThreads(threads)
    check seen > 0
    check leftovers(dir).len == 0
  test "a write that fails leaves no part file, and the old file as it was":
    removeDir(dir)
    createDir(dir / "target") # (a directory where the file should go: the rename fails)
    expect OSError:
      writeAtomic(dir / "target", "text")
    check leftovers(dir).len == 0
    let path = dir / "kept.txt"
    writeAtomic(path, "old")
    expect CatchableError:
      writeAtomic(path / "inside", "x") # (the directory cannot be made: kept.txt is a file)
    check readFile(path) == "old" and leftovers(dir).len == 0

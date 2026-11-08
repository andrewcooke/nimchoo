import std/[asyncdispatch, monotimes, os, strutils, times, unittest]
import nimchoo/serve/[handler, workers]

# (the program run is /bin/sh, and its "arguments" are `-c SCRIPT`: the workers do not care what the program is)

let dir = getTempDir() / "nch-test-serve-workers"

proc script(w: Workers, text: string): Future[WorkerResult] =
  w.run(@["-c", text])

proc ms(since: MonoTime): int64 =
  (getMonoTime() - since).inMilliseconds

suite "serve workers":
  test "a worker's output, error and exit code":
    let w = newWorkers("/bin/sh")
    let r = waitFor w.script("echo out; echo err >&2; exit 3")
    check r.stdout == "out\n" and r.stderr == "err\n" and r.code == 3
  test "different pages are made at the same time":
    let w = newWorkers("/bin/sh")
    let t0 = getMonoTime()
    let rs = waitFor all(@[w.script("sleep 0.5; echo a"), w.script("sleep 0.5; echo b"), w.script("sleep 0.5; echo c")])
    check rs[0].stdout == "a\n" and rs[1].stdout == "b\n" and rs[2].stdout == "c\n"
    check t0.ms < 1300
  test "requests for the same page share one run":
    removeDir(dir)
    createDir(dir)
    let w = newWorkers("/bin/sh")
    # (each run adds a line to a file)
    let s = "echo x >> " & (dir / "runs") & "; sleep 0.3; echo page"
    let rs = waitFor all(@[w.script(s), w.script(s), w.script(s)])
    check rs[0].stdout == "page\n" and rs[1].stdout == "page\n" and rs[2].stdout == "page\n"
    check readFile(dir / "runs").splitLines.len == 2 # one line and the end
    # and when it is over, a new request runs again
    discard waitFor w.script(s)
    check readFile(dir / "runs").splitLines.len == 3
  test "no more than the limit run at once; the others wait their turn":
    let w = newWorkers("/bin/sh", limit = 2)
    let t0 = getMonoTime()
    let rs = waitFor all(@[
      w.script("sleep 0.4; echo 1"), w.script("sleep 0.4; echo 2"),
      w.script("sleep 0.4; echo 3"), w.script("sleep 0.4; echo 4")])
    check rs[3].stdout == "4\n"
    check t0.ms >= 780 and t0.ms < 2500 # two rounds of 0.4 s
  test "a worker that takes too long is killed, and the page says so":
    let w = newWorkers("/bin/sh", timeoutMs = 400)
    let r = waitFor w.script("echo before; sleep 30")
    check r.code != 0 and "stopped after" in r.stderr
  test "a program that is not there":
    let w = newWorkers("/nonexistent/nch")
    let r = waitFor w.run(@["map"])
    check r.code != 0 and "cannot run" in r.stderr

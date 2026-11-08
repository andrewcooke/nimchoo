import std/[asyncdispatch, monotimes, times, unittest]
import nimchoo/[child, childasync]

proc sh(script: string, ms = 5000): ChildResult =
  runChild("/bin/sh", @["-c", script], ms)

suite "child processes":
  test "output, error and the exit code":
    let r = sh("echo out; echo err >&2; exit 3")
    check r.stdout == "out\n" and r.stderr == "err\n" and r.code == 3 and not r.timedOut
  test "a child that fills the error pipe while the output is waited for does not deadlock":
    # (more than a pipe holds, on stderr first, then a little on stdout)
    let r = sh("head -c 300000 /dev/zero >&2; echo done")
    check r.stderr.len == 300000 and r.stdout == "done\n" and r.code == 0
  test "both pipes full at once":
    let r = sh("head -c 200000 /dev/zero & head -c 200000 /dev/zero >&2; wait")
    check r.stdout.len == 200000 and r.stderr.len == 200000
  test "a child that hangs is killed at the time limit, and what it said is kept":
    let t0 = getMonoTime()
    let r = sh("echo before; sleep 30", 400)
    check r.timedOut and r.code == timedOutCode and r.stdout == "before\n"
    check (getMonoTime() - t0).inMilliseconds < 5000
  test "a child that closes its outputs and carries on is killed too":
    let r = sh("exec >&- 2>&-; sleep 30", 400)
    check r.timedOut and r.code == timedOutCode
  test "a program that is not there":
    let r = runChild("/nonexistent/program", @[], 1000)
    check r.code == notStarted and r.stderr.len > 0
  test "arguments are not given to a shell":
    let r = runChild("/bin/echo", @["a b", "$HOME;ls"], 1000)
    check r.stdout == "a b $HOME;ls\n"

proc ms(since: MonoTime): int64 =
  (getMonoTime() - since).inMilliseconds

suite "child processes: without stopping the event loop":
  test "the same results as the blocking one":
    let r = waitFor runChildAsync("/bin/sh", @["-c", "head -c 300000 /dev/zero >&2; echo out; exit 2"], 5000)
    check r.stderr.len == 300000 and r.stdout == "out\n" and r.code == 2
  test "three children that take 0.5 s each take about 0.5 s together":
    let t0 = getMonoTime()
    let all = waitFor all(
      @[
        runChildAsync("/bin/sh", @["-c", "sleep 0.5; echo a"], 5000),
        runChildAsync("/bin/sh", @["-c", "sleep 0.5; echo b"], 5000),
        runChildAsync("/bin/sh", @["-c", "sleep 0.5; echo c"], 5000),
      ]
    )
    check all[0].stdout == "a\n" and all[2].stdout == "c\n"
    check t0.ms < 1300
  test "the loop keeps running while a child does":
    var ticks = 0
    proc ticker() {.async.} =
      for _ in 1 .. 10:
        await sleepAsync(20)
        inc ticks
    let child = runChildAsync("/bin/sh", @["-c", "sleep 0.6"], 5000)
    waitFor ticker() # (about 0.2 s)
    check ticks == 10 and not child.finished
    check waitFor(child).code == 0
  test "a hung child is killed at the limit":
    let t0 = getMonoTime()
    let r = waitFor runChildAsync("/bin/sh", @["-c", "echo before; sleep 30"], 400)
    check r.timedOut and r.code == timedOutCode and r.stdout == "before\n"
    check t0.ms < 5000
  test "a program that is not there":
    check waitFor(runChildAsync("/nonexistent/program", @[], 1000)).code == notStarted

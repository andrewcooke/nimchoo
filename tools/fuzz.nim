## `nimble fuzz TARGET [SECONDS]`: build the libFuzzer harness tests/fuzz/TARGET.nim with clang and run it (default 60 s).
##
## Level 2 of the fuzzing in REVIEW.md: coverage-guided, so it reaches code that the random damage of the level-1 tests
## (tests/*/test_fuzz.nim, which are part of nimble test) does not.  Not run by the tests.  What it needs is clang with
## its libFuzzer and address sanitizer runtimes.
##
## * the corpus is `fuzz-corpus/TARGET/` (git-ignored; started from valid examples if empty);
## * an input that makes the harness fail is written to `tests/data/fuzz/TARGET/` (crash-HASH, oom-HASH, timeout-HASH), where
##   the level-1 test of the target replays it: fix the bug (a test first), and keep the file;
## * the harness is built to `fuzz-bin/` (git-ignored) with `--panics:on` (a Defect aborts, which is a crash to libFuzzer).
##   The address sanitizer (with `-d:useMalloc`, so that it sees Nim's memory) is on only for the targets that go through
##   zippy, whose inflate code is unsafe (zip, xlsx, profile): the other readers are Nim without pointers, and it makes
##   them 4 times slower (fit: 120 runs a second with it, 500 without).

import std/[algorithm, os, osproc, parseutils, sequtils, strformat, strutils]
import ../src/nimchoo/packages/selection/bits
import ../tests/support/[fuzzfiles, fuzzsamples, xlsxbuilder, zips]

const
  targets = ["fit", "importer", "bits", "zip", "xlsx", "profile", "request"]
  fitDirs = ["sdk", "other", "python-fitparse"]
  withAddressSanitizer = ["zip", "xlsx", "profile"]

func maxLen(target: string): int =
  ## The longest input libFuzzer makes: a little over what the reader accepts, where it limits the input.
  case target
  of "bits":
    maxChars + 1
  of "request":
    8100
  of "fit", "importer":
    16_384
  else:
    65_536

proc gccInstallDir(): string =
  ## The newest GCC installation that has `libstdc++.so`.  clang chooses the newest GCC it finds, which may be one that
  ## lacks it (GCC 16 on openSUSE, with only 15's `libstdc++-devel`), and then linking fails with `cannot find -lstdc++`.
  var found: seq[(int, string)] # (major version, directory)
  for lib in walkPattern("/usr/lib*/gcc/*/*/libstdc++.so"):
    let dir = parentDir(lib)
    var major = 0
    discard parseInt(extractFilename(dir), major)
      # (the directory is named for the version: "15", or "13.2.0")
    found.add (major, dir)
  found.sort()
  if found.len > 0:
    found[^1][1]
  else:
    ""

proc seed(target, dir: string) =
  ## Valid inputs for libFuzzer to start from.
  createDir(dir)
  var n = 0
  proc put(name, content: string) =
    inc n
    writeFile(dir / fmt"seed-{n:03}-{name}", content)

  case target
  of "fit", "importer":
    for path in fitFiles(0, 12_000, fitDirs):
      put(extractFilename(path), readFile(path))
  of "bits":
    for ids in [
      @[1'i64],
      @[156'i64, 159, 165, 582, 682, 696],
      @[200'i64, 201, 202, 203, 260],
      @[1'i64, 2, 3, 10, 11, 500],
    ]:
      put("bits", encodeBits(ids))
  of "request":
    for a in requestAddresses:
      put("address", a)
  of "zip":
    for z in zipBases():
      put("zip", z)
  of "xlsx":
    put("stored", storedZip(xlsxParts))
    put("deflated", makeZip(xlsxParts))
  of "profile":
    put("small", smallProfile())
  else:
    discard

proc main(): int =
  let args = commandLineParams()
  if args.len notin 1 .. 2 or args[0] notin targets:
    let names = targets.join("|")
    echo fmt"usage: nimble fuzz TARGET [SECONDS]   (TARGET: {names})"
    return 2
  let target = args[0]
  let seconds =
    if args.len == 2:
      parseInt(args[1])
    else:
      60
  if findExe("clang").len == 0:
    echo "clang is not installed (it is needed for libFuzzer)"
    return 1
  let gcc = gccInstallDir()
  let gccFlag =
    if gcc.len > 0:
      " --gcc-install-dir=" & gcc
    else:
      ""
  let asan = target in withAddressSanitizer
  let sanitize = if asan: "fuzzer,address" else: "fuzzer"
  let malloc = if asan: " -d:useMalloc" else: ""
  let bin = "fuzz-bin" / target
  createDir("fuzz-bin")
  let build =
    fmt"nim c --cc:clang --noMain:on -d:release --checks:on --panics:on{malloc} --hints:off " &
    fmt"--nimcache:fuzz-bin/cache-{target} " &
    fmt""" --passC:"-fsanitize={sanitize}{gccFlag}" --passL:"-fsanitize={sanitize}{gccFlag}" """ &
    fmt"-o:{bin} tests/fuzz/{target}.nim"
  echo build
  if execCmd(build) != 0:
    return 1
  let corpus = "fuzz-corpus" / target
  if not dirExists(corpus) or toSeq(walkFiles(corpus / "*")).len == 0:
    seed(target, corpus)
  let crashes = "tests/data/fuzz" / target
  createDir(crashes)
  let run =
    fmt"{bin} -max_total_time={seconds} -max_len={maxLen(target)} -timeout=10 -rss_limit_mb=2048 " &
    fmt"-print_final_stats=1 -artifact_prefix={crashes}/ {corpus}"
  echo run
  let code = execCmd(run)
  if code != 0:
    echo fmt"""
the harness stopped with status {code}: the input is in {crashes}/ (crash-, oom- or timeout-).  Fix the bug (write a test
first: the level-1 test of the target replays what is in that directory), and keep the file."""
  code

quit main()

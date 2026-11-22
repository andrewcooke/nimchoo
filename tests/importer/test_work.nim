## What one file comes to before it is written: decoded, known, or failed, as a value that cannot hold what does not belong.

import std/[os, unittest]
import nimchoo/core/errors
import nimchoo/packages/fit/load
import nimchoo/packages/importer/[failure, importer, work]

let dir = getTempDir() / "nch-test-work"

let noProfile: ProfileSource = proc(): Profile {.
    closure, raises: [ProfileError, XlsxError]
.} =
  raiseProfile("no such profile", "Types", 0)

let notKnown: KnownCheck = proc(digest: string): bool {.closure, raises: [].} =
  false

suite "work: preparing a file":
  test "a file that cannot be read fails as unreadable, which is not remembered":
    let p = prepareFile(
      noProfile, @[], notKnown, Job(stop: false, index: 3, path: dir / "nothing.fit")
    )
    check p.outcome == poFailed and p.failure == fkUnreadable and p.index == 3
    check not p.failure.remembered
  test "a profile that cannot be loaded fails the file as the profile's fault, which is not remembered (no empty profile stands in)":
    createDir(dir)
    writeFile(dir / "a.fit", "not fit at all, but long enough to be read")
    let p = prepareFile(
      noProfile, @[], notKnown, Job(stop: false, index: 0, path: dir / "a.fit")
    )
    check p.outcome == poFailed and p.failure == fkProfile
    check p.message.len > 0 and not p.failure.remembered
  test "a known content is not decoded, and the profile is not asked for":
    createDir(dir)
    writeFile(dir / "b.fit", "x")
    let known: KnownCheck = proc(digest: string): bool {.closure, raises: [].} =
      true
    let p = prepareFile(
      noProfile, @[], known, Job(stop: false, index: 1, path: dir / "b.fit")
    )
    check p.outcome == poKnown and p.digest.len == 64

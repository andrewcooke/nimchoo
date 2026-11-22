## The part of importing a file that needs no database: read it, hash it, decode it.  Everything that
## comes out is plain data (and a failure is data too, not an exception), so this can run on any
## thread and the result can be handed to the one that writes the database (pool.nim).

import std/[monotimes, times]
import ../../core/errors
import ../util/bytes/bytes
import ../util/hashing/hashing
import ../util/profiling/profiling
import ../util/warnings/warnings
import ./failure
import ./importer

{.push raises: [].}

type
  Job* = object
    case stop*: bool
    of false:
      index*: int ## which file (its place among the files to look at)
      path*: string
    of true:
      discard ## tells a worker to end

  PrepOutcome* = enum
    poDecoded ## decoded: the activities are in `decoded`
    poKnown ## its content is in the database already (nothing was decoded)
    poFailed ## it could not be read or decoded: see `failure` and `message`

  Prepared* = object
    index*: int
    bytes*: int ## size of the file
    nanos*: int64 ## how long this took
    digest*: string ## SHA-256 of the contents
    warnings*: seq[Warning] ## noticed while decoding (also when it then failed)
    case outcome*: PrepOutcome
    of poDecoded:
      decoded*: Decoded
    of poKnown:
      discard
    of poFailed:
      failure*: FailureKind
      message*: string

type KnownCheck* = proc(digest: string): bool {.closure, raises: [].}
  ## Whether a content (its hash) is in the database already.

proc prepareFile*(
    profile: ProfileSource, channels: seq[string], isKnown: KnownCheck, job: Job
): Prepared =
  ## Read, hash and decode the file.  A file whose content `isKnown` is not decoded (and `profile`,
  ## which can be costly to make, is asked for only when a file is decoded).
  doAssert not job.stop
  let t0 = getMonoTime()
  proc took(): int64 =
    (getMonoTime() - t0).inNanoseconds

  var data: seq[byte]
  try:
    timed "read file":
      data = readBytes(job.path)
  except IOError as e:
    return Prepared(
      index: job.index,
      outcome: poFailed,
      failure: fkUnreadable,
      message: e.msg,
      nanos: took(),
    )
  var digest = ""
  timed "hash":
    digest = sha256Hex(data)
  if isKnown(digest):
    return Prepared(
      index: job.index, outcome: poKnown, bytes: data.len, digest: digest, nanos: took()
    )
  var warnings: seq[Warning]
  try:
    let decoded = decodeFile(profile(), data, channels, warnings)
    Prepared(
      index: job.index,
      outcome: poDecoded,
      bytes: data.len,
      digest: digest,
      decoded: decoded,
      warnings: warnings,
      nanos: took(),
    )
  except NchError as e:
    Prepared(
      index: job.index,
      outcome: poFailed,
      bytes: data.len,
      digest: digest,
      warnings: warnings,
      failure: failureOf(e),
      message: e.msg,
      nanos: took(),
    )

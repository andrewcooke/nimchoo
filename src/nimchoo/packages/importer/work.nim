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
    index*: int ## which file (its place among the files to look at); negative: stop
    path*: string

  PrepOutcome* = enum
    poDecoded ## decoded: the activities are in `decoded`
    poKnown ## its content is in the database already (nothing was decoded)
    poFailed ## it could not be read or decoded: see `failure` and `message`

  Prepared* = object
    index*: int
    outcome*: PrepOutcome
    bytes*: int ## size of the file
    nanos*: int64 ## how long this took
    digest*: string ## SHA-256 of the contents
    decoded*: Decoded
    warnings*: seq[Warning] ## noticed while decoding (also when it then failed)
    failure*: FailureKind
    message*: string

type KnownCheck* = proc(digest: string): bool {.closure, raises: [].}
  ## Whether a content (its hash) is in the database already.

proc prepareFile*(
    profile: ProfileSource, channels: seq[string], isKnown: KnownCheck, job: Job
): Prepared =
  ## Read, hash and decode the file.  A file whose content `isKnown` is not decoded (and `profile`,
  ## which can be costly to make, is asked for only when a file is decoded).
  let t0 = getMonoTime()
  result.index = job.index
  var data: seq[byte]
  try:
    timed "read file":
      data = readBytes(job.path)
  except IOError as e:
    result.outcome = poFailed
    result.failure = fkUnreadable
    result.message = e.msg
    result.nanos = (getMonoTime() - t0).inNanoseconds
    return
  result.bytes = data.len
  timed "hash":
    result.digest = sha256Hex(data)
  if isKnown(result.digest):
    result.outcome = poKnown
  else:
    try:
      result.decoded = decodeFile(profile(), data, channels, result.warnings)
      result.outcome = poDecoded
    except NchError as e:
      result.outcome = poFailed
      result.failure = failureOf(e)
      result.message = e.msg
  result.nanos = (getMonoTime() - t0).inNanoseconds

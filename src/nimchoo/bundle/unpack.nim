## The files built into the program that are also kept as files in the cache directory's `system/`
## part (the FIT profile, the licence notice, the page templates), and which one
## to use.
##
## The program carries each file (`Bundle`).  The first time it is wanted it is unpacked, and the
## hash of what was unpacked is written in the *manifest* (a file at the top of the cache directory).
## After that:
##
##   * a file that is missing is unpacked again (so `system/` can always be deleted);
##   * a file that is still as it was unpacked is untouched by the author, so a newer version in the
##     program replaces it;
##   * a file that is different was put there (or changed) by the author, say a newer FIT SDK profile:
##     it is used as it is and never overwritten.
##
## The decision (`decide`) and the manifest are pure; `resolve` does the files.  A cache directory that
## cannot be used is never an error: the program's own copy is used.

import std/[algorithm, options, os, strutils, tables]
import ../cache
import ../hashing

{.push raises: [].}

type
  Bundle* = object
    name*: string ## the file's name in `system/`
    data*: string ## what the program carries

  Action* = enum
    acUnpack ## the file is missing: unpack it
    acRefresh
      ## the file is as unpacked before, and the program has a newer one: replace it
    acCurrent ## the file is what the program carries
    acCustom ## the file is not what was unpacked: use it, never overwrite it

  Source* = enum
    soBundled ## the program's copy (the cache could not be used)
    soUnpacked ## the file in `system/` (the program's, just unpacked or replaced)
    soCustom ## the author's file in `system/`

  Resolved* = object
    data*: string
    source*: Source
    path*: string ## the file in `system/` ("" if there is none)
    hash*: string ## the SHA-256 of `data` (already worked out, so a caller need not)

const
  manifestName* = "manifest"
  noticeBundle* = Bundle(name: "NOTICE", data: staticRead("../../../NOTICE"))
    ## The licence notice (the data and libraries the program carries and their licences): kept as a
    ## file in `system/` so that it can be read, and unpacked whenever anything else is.  Nothing
    ## reads it back.

func decide*(fileHash, recorded: Option[string], bundled: string): Action =
  ## What to do about a bundled file, given the hash of the file in `system/` (none if it is not
  ## there), the hash recorded when it was unpacked (none if nothing is recorded) and the hash of
  ## the program's copy.
  if fileHash.isNone:
    return acUnpack
  if fileHash.get == bundled:
    return acCurrent
  if recorded.isSome and recorded.get == fileHash.get:
    return acRefresh
  acCustom

func parseManifest*(text: string): Table[string, string] =
  ## `hash  name` lines (lines that are not that are ignored).
  for line in text.splitLines:
    let sep = line.find("  ")
    if sep == 64 and line.len > 66:
      result[line[66 .. ^1]] = line[0 ..< 64]

func formatManifest*(entries: Table[string, string]): string =
  ## The manifest text, sorted by name so that it does not change for nothing.
  var lines: seq[(string, string)] # (name, hash)
  for k, v in entries:
    lines.add (k, v)
  lines.sort()
  for (k, v) in lines:
    result.add v & "  " & k & "\n"

proc readManifest(top: string): Table[string, string] =
  try:
    result = parseManifest(readFile(top / manifestName))
  except IOError:
    discard

proc record(top, name, hash: string) =
  ## Write the hash of what was unpacked.  (A failure only means the file counts as the author's
  ## next time, which is why a file equal to the program's own is always `acCurrent` first.)
  var entries = readManifest(top)
  entries[name] = hash
  try:
    createDir top
    let tmp = top / manifestName & ".part"
    writeFile(tmp, formatManifest(entries))
    moveFile(tmp, top / manifestName)
  except IOError, OSError, Exception:
    discard

proc resolve*(top: string, b: Bundle): Resolved {.gcsafe.} =
  ## The data to use for a bundled file, unpacking it into `top`'s `system/` if need be.  `top` is
  ## the cache directory; "" means there is none (use the program's copy).
  let bundled = sha256Hex(b.data)
  let program = Resolved(data: b.data, source: soBundled, hash: bundled)
    # (the program's copy)
  if top.len == 0:
    return program
  let path = systemDir(top) / b.name
  var current: Option[string]
  var onDisk = ""
  try:
    if fileExists(path):
      onDisk = readFile(path)
      current = some(sha256Hex(onDisk))
  except IOError, OSError:
    return program # unreadable: the program's copy will do
  var recorded = none(string)
  for k, v in readManifest(top):
    if k == b.name:
      recorded = some(v)
  case decide(current, recorded, bundled)
  of acCustom:
    return Resolved(data: onDisk, source: soCustom, path: path, hash: current.get)
  of acCurrent:
    if recorded != some(bundled):
      record(top, b.name, bundled)
    return Resolved(data: b.data, source: soUnpacked, path: path, hash: bundled)
  of acUnpack, acRefresh:
    if b.name != noticeBundle.name:
      discard resolve(top, noticeBundle) # (the notice goes with them)
    try:
      createDir parentDir(path)
      let tmp = path & ".part"
      writeFile(tmp, b.data)
      moveFile(tmp, path)
    except IOError, OSError, Exception:
      return program # cannot write: the program's copy will do
    record(top, b.name, bundled)
    return Resolved(data: b.data, source: soUnpacked, path: path, hash: bundled)

proc unpackNotice*(top: string) =
  ## Put NOTICE in `top`'s `system/` part, if it is not already there.
  discard resolve(top, noticeBundle)

proc resolve*(b: Bundle): Resolved =
  ## ... in the cache directory the environment points to (see cache.nim).
  let dir = cacheDir()
  resolve(if dir.isSome: dir.get else: "", b)

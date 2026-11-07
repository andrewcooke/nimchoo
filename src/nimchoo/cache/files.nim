## The files outside the database, by kind: what is in the cache directory (see ../cache.nim) and
## what can be deleted from it.  Every kind is made again when it is needed (downloaded, generated or
## unpacked from the program), so deleting one loses nothing but the time.  The server's token is
## not a kind and is never touched.

import std/[os, strutils]
import ../cache
import ../download/fetch

{.push raises: [].}

type
  Kind* = enum
    ckDownloads = "downloads"
      ## fetched from the net (the GeoNames country files): `data/`
    ckSystem = "system" ## unpacked from the program (the profile, templates): `system/`
    ckGeojson = "geojson" ## made by commands: `user/*.geojson`
    ckCsv = "csv" ## made by commands: `user/*.csv`
    ckHtml = "html" ## made by commands: `user/*.html`

  Use* = object
    count*: int
    bytes*: int64

const kindHelp*: array[Kind, string] = [
  "files fetched from the net (the GeoNames country files); fetched again when a place needs them",
  "files unpacked from the program (the profile, the licence notice, page templates); unpacked again",
  "maps made by commands", "tables made by commands", "web pages made by commands",
]

func kindNames*(): string =
  ## "downloads, system, geojson, csv, html"
  for k in Kind:
    if result.len > 0:
      result.add ", "
    result.add $k

func parseKind*(s: string, kind: var Kind): bool =
  ## Whether `s` names a kind (case does not matter).
  for k in Kind:
    if $k == s.toLowerAscii:
      kind = k
      return true

func describe*(use: Use): string =
  ## "12 files (3.4MB)", "1 file (12kB)", "no files".
  if use.count == 0:
    return "no files"
  $use.count & (if use.count == 1: " file" else: " files") & " (" & humanBytes(
    use.bytes
  ) & ")"

proc walkFiles(dir: string, extension = ""): seq[string] =
  ## The files below `dir` (all levels), or those directly in it with the extension; none if there is no such directory.
  try:
    if extension.len == 0:
      for path in walkDirRec(dir):
        result.add path
    else:
      for kind, path in walkDir(dir):
        if kind == pcFile and path.endsWith("." & extension):
          result.add path
  except OSError:
    discard

proc filesOf(dir: string, kind: Kind): seq[string] =
  case kind
  of ckDownloads:
    walkFiles(dataDir(dir))
  of ckSystem:
    walkFiles(systemDir(dir))
  of ckGeojson, ckCsv, ckHtml:
    walkFiles(userDir(dir), $kind)

proc useOf*(dir: string, kind: Kind): Use =
  ## What there is of the kind (nothing if the directory is missing).
  for path in filesOf(dir, kind):
    try:
      result.bytes += getFileSize(path)
      inc result.count
    except OSError:
      discard

proc deleteKind*(dir: string, kind: Kind): Use =
  ## Delete the files of the kind; returns what was there.  A file that cannot be deleted is left (and not counted).
  ## The directories of `downloads` and `system` go too.
  for path in filesOf(dir, kind):
    try:
      let size = getFileSize(path)
      removeFile path
      inc result.count
      result.bytes += size
    except OSError:
      discard
  try:
    case kind
    of ckDownloads:
      removeDir dataDir(dir)
    of ckSystem:
      removeDir systemDir(dir)
    else:
      discard
  except OSError, Exception:
    discard

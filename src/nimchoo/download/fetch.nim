## Fetching a source into the cache: the one place where nch uses the network.
##
## Before anything is fetched the room is checked (the cache's disk must keep 500 MB free after the file,
## and its contents, are in) and so is the size the server announces against the most the source may
## be; what comes back is checked (a zip must be one, and hold the entry expected) and is written
## atomically, so a file in the cache is whole.  Nothing is printed: what happens is told to a `Sink`
## as events (a command passes a sink that logs and says them; a test passes one that collects them),
## and a file already in the cache is returned without a word.  The network and the disk are
## passed in (`Env`), so tests serve made-up bytes and a made-up amount of room.

import std/[httpclient, options, os, strutils, tables]
import ../errors
import ../lookup
import ../zipbytes
import ./sources
when defined(posix):
  import std/posix

{.push raises: [].}

const
  reserveBytes* = 500'i64 * 1024 * 1024     ## left free on the disk after a download
  spaceFactor* = 3'i64                      ## the file, and what is made from it (the database, a copy)
  userAgent = "nimchoo (https://github.com/andrewcooke/nimchoo)"

type
  FetchResult* = object
    ok*: bool
    status*: int
    body*: string
    message*: string          ## why not, if not ok

  Fetcher* = object
    head*: proc(url: string): Option[int64] {.closure, raises: [].}     ## the size the server announces
    get*: proc(url: string): FetchResult {.closure, raises: [].}

  Env* = object
    fetcher*: Fetcher
    freeBytes*: proc(dir: string): Option[int64] {.closure, raises: [].}   ## room on the disk holding `dir`

  EventKind* = enum deStarting, deDownloaded, deFailed

  DownloadEvent* = object
    kind*: EventKind
    source*: string           ## the source's name
    url*: string
    path*: string             ## where it is now (deDownloaded)
    bytes*: int64             ## how big (deDownloaded)
    message*: string          ## why it is wanted (deStarting), or why not (deFailed)

  Sink* = proc(ev: DownloadEvent) {.closure, raises: [].}

  DataUsage* = object
    files*: int
    bytes*: int64

func humanBytes*(n: int64): string =
  ## "1.4 MB", "85 kB", "12 bytes".
  if n >= 1_000_000: formatFloat(float(n) / 1e6, ffDecimal, 1) & " MB"
  elif n >= 1_000: $(n div 1_000) & " kB"
  else: $n & " bytes"

func describe*(ev: DownloadEvent): string =
  ## One line for people.
  case ev.kind
  of deStarting: "need " & ev.message
  of deDownloaded: "downloaded " & ev.url & " (" & humanBytes(ev.bytes) & ")"
  of deFailed: "cannot download " & ev.url & ": " & ev.message

proc silent*(): Sink =
  ## A sink that ignores every event.
  result = proc(ev: DownloadEvent) {.closure, raises: [].} =
    discard

# --- the real network and disk

proc realFetcher*(timeoutMs = 60_000): Fetcher =
  ## HTTP and HTTPS by `std/httpclient` (HTTPS needs the program built with -d:ssl and OpenSSL installed).
  result.head = proc(url: string): Option[int64] {.closure, raises: [].} =
    try:
      let c = newHttpClient(userAgent = userAgent, timeout = timeoutMs)
      defer: c.close()
      let r = c.head(url)
      if r.code.is2xx and r.headers.hasKey("content-length"):
        return some(parseBiggestInt(r.headers["content-length"]))
    except Exception:           # (httpclient is declared to raise anything)
      discard
  result.get = proc(url: string): FetchResult {.closure, raises: [].} =
    try:
      let c = newHttpClient(userAgent = userAgent, timeout = timeoutMs)
      defer: c.close()
      let r = c.get(url)
      if r.code.is2xx:
        return FetchResult(ok: true, status: int(r.code), body: r.body)
      return FetchResult(ok: false, status: int(r.code), message: "the server said " & r.status)
    except Exception:           # (httpclient is declared to raise anything)
      return FetchResult(ok: false, message: getCurrentExceptionMsg())

proc realFreeBytes*(dir: string): Option[int64] {.raises: [].} =
  ## Room left on the disk that holds `dir` (or the nearest directory above it that exists).
  when defined(posix):
    var path = dir
    while path.len > 1 and not dirExists(path): path = parentDir(path)
    var s: Statvfs
    if statvfs(cstring(path), s) == 0:
      return some(int64(s.f_bavail) * int64(s.f_frsize))
  none(int64)

proc realEnv*(): Env =
  Env(fetcher: realFetcher(), freeBytes: realFreeBytes)

# --- fetching

proc fail(sink: Sink, src: Source, url, why: string): Option[string] =
  sink(DownloadEvent(kind: deFailed, source: src.name, url: url, message: why))
  none(string)

proc checkContent(src: Source, arg, body: string): string =
  ## "" if what came is what was asked for, else what is wrong with it.
  if body.len == 0: return "the file is empty"
  if src.zipEntry.len == 0: return ""
  let want = entryFor(src, arg)
  try:
    let entries = listEntries(body)
    if want notin entries: return "the zip has no " & want
    if entries.must(want).size == 0: return "the zip's " & want & " is empty"
  except ZipError as e:
    return "not a zip file (" & e.msg & ")"
  ""

proc fetchSource*(env: Env, sink: Sink, dataDir: string, src: Source, arg = ""): Option[string] =
  ## The path of the source's file in the cache: already there, or fetched now.  None if it could
  ## not be had (a failed event says why).
  let dir = dataDir / src.name
  let path = dir / fileFor(src, arg)
  try:
    if fileExists(path) and getFileSize(path) > 0: return some(path)
  except OSError:
    discard
  let url = urlFor(src, arg)
  sink(DownloadEvent(kind: deStarting, source: src.name, url: url, message: whyFor(src, arg)))
  # the size, and the room
  let announced = env.fetcher.head(url)
  if announced.isSome and announced.get > src.maxBytes:
    return fail(sink, src, url, "the file is " & humanBytes(announced.get) & ", more than the " &
                humanBytes(src.maxBytes) & " allowed")
  let size = if announced.isSome: announced.get else: src.maxBytes
  let need = size * spaceFactor + reserveBytes
  let free = env.freeBytes(dataDir)
  if free.isSome and free.get < need:
    return fail(sink, src, url, "not enough room on the disk: " & humanBytes(need) &
                " wanted (the file, what is made from it and " & humanBytes(reserveBytes) &
                " to spare), " & humanBytes(free.get) & " free")
  # the file
  let r = env.fetcher.get(url)
  if not r.ok:
    return fail(sink, src, url, r.message)
  if int64(r.body.len) > src.maxBytes:
    return fail(sink, src, url, "the file is " & humanBytes(int64(r.body.len)) & ", more than the " &
                humanBytes(src.maxBytes) & " allowed")
  let problem = checkContent(src, arg, r.body)
  if problem.len > 0:
    return fail(sink, src, url, problem)
  try:
    createDir(dir)
    let tmp = path & ".part"
    writeFile(tmp, r.body)
    moveFile(tmp, path)
  except IOError, OSError:
    return fail(sink, src, url, "cannot write " & path & ": " & getCurrentExceptionMsg())
  except Exception:                 # (moveFile is declared to raise anything)
    return fail(sink, src, url, "cannot write " & path)
  sink(DownloadEvent(kind: deDownloaded, source: src.name, url: url, path: path, bytes: int64(r.body.len)))
  some(path)

# --- what is there

proc dataUsage*(dataDir: string): DataUsage =
  ## How many files, and how many bytes, the downloads take.
  try:
    for path in walkDirRec(dataDir):
      inc result.files
      result.bytes += getFileSize(path)
  except OSError:
    discard

proc clearData*(dataDir: string): DataUsage =
  ## Delete the downloaded files; returns what was there.
  result = dataUsage(dataDir)
  try:
    removeDir(dataDir)
  except OSError:
    discard
  except Exception:
    discard

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
import ../core/errors
import ../lookup
import ../[atomic, zipbytes, zipchild]
import ./sources
when defined(posix):
  import std/posix

{.push raises: [].}

const
  reserveBytes* = 500'i64 * 1024 * 1024 ## left free on the disk after a download
  spaceFactor* = 3'i64 ## the file, and what is made from it (the database, a copy)
  userAgent = "nimchoo (https://github.com/andrewcooke/nimchoo)"

type
  FetchResult* = object
    ok*: bool
    status*: int
    body*: string
    message*: string ## why not, if not ok

  Tick* = proc(done, total: int64) {.closure, raises: [].}
    ## told how much has come (`total` 0: not known)

  Fetcher* = object
    head*: proc(url: string): Option[int64] {.closure, raises: [].}
      ## the size the server announces
    get*: proc(url: string): FetchResult {.closure, raises: [].}
    getTelling*: proc(url: string, tick: Tick, maxBytes: int64): FetchResult {.
      closure, raises: []
    .}
      ## like `get`, but tells `tick` as the body comes, and stops reading when more than `maxBytes` have come (what the
      ## server announced is a claim; this is the limit on what arrives).  nil: the fetcher cannot, and `get` is used

  Env* = object
    fetcher*: Fetcher
    freeBytes*: proc(dir: string): Option[int64] {.closure, raises: [].}
      ## room on the disk holding `dir`
    inflater*: Inflater
      ## how the zips it fetched are inflated (nil: here; the real one does it in a child with a memory ceiling)

  EventKind* = enum
    deStarting
    deProgress
    deDownloaded
    deReading
    deFinished
    deFailed
    deWorking
    deWorkDone
      ## deWorking / deWorkDone: a command's own long job (naming the activities) begins and ends, said with a spinner that
      ## steps aside for the downloads inside it.  The first four: a file is wanted, some of it came, all of it came; then the consumer reads it (deReading, also
      ## for a file that was already in the cache) and is done with it (deFinished)

  DownloadEvent* = object
    kind*: EventKind
    source*: string ## the source's name
    url*: string
    path*: string ## where it is now (deDownloaded)
    bytes*: int64 ## how big (deDownloaded), or how much has come (deProgress)
    total*: int64 ## how big it will be, 0 if not known (deProgress)
    label*: string ## a few words for the screen: what is wanted (deStarting)
    message*: string ## why it is wanted (deStarting), or why not (deFailed)

  Sink* = proc(ev: DownloadEvent) {.closure, raises: [].}

  DataUsage* = object
    files*: int
    bytes*: int64

func humanBytes*(n: int64): string =
  ## "1.4MB", "85kB", "12B": no space before the unit.
  if n >= 1_000_000:
    formatFloat(float(n) / 1e6, ffDecimal, 1) & "MB"
  elif n >= 1_000:
    $(n div 1_000) & "kB"
  else:
    $n & "B"

func shortUrl*(url: string): string =
  ## The address without "https://" (or "http://"), for the screen.
  if url.startsWith("https://"):
    url[8 .. ^1]
  elif url.startsWith("http://"):
    url[7 .. ^1]
  else:
    url

func describe*(ev: DownloadEvent): string =
  ## One line for people.
  case ev.kind
  of deStarting:
    "need " & ev.label & ": " & shortUrl(ev.url)
  of deProgress:
    "downloading " & shortUrl(ev.url) & " (" & humanBytes(ev.bytes) & ")"
  of deDownloaded:
    "downloaded " & shortUrl(ev.url) & " (" & humanBytes(ev.bytes) & ")"
  of deReading:
    "reading " & shortUrl(ev.url)
  of deFinished, deWorking, deWorkDone:
    ""
  of deFailed:
    "cannot download " & shortUrl(ev.url) & ": " & ev.message

# --- the real network and disk

type TooBig* = object of CatchableError
  ## more has come than the limit allows: the download is stopped

proc checkProgress*(progress, maxBytes: int64) {.raises: [TooBig].} =
  ## Called as the body comes, with the bytes so far: stops the download once more than `maxBytes` have come.  (The
  ## size the server announces is only a claim; this is the limit on what really arrives.)  `httpclient` reports at
  ## most once a second, so what has come can pass the limit by up to a second of the link's speed: the memory is
  ## bounded, not exact.
  if progress > maxBytes:
    raise newException(
      TooBig,
      "more than the " & humanBytes(maxBytes) & " allowed came; the download was stopped",
    )

proc realFetcher*(timeoutMs = 60_000): Fetcher =
  ## HTTP and HTTPS by `std/httpclient` (HTTPS needs the program built with -d:ssl and OpenSSL installed).
  result.head = proc(url: string): Option[int64] {.closure, raises: [].} =
    try:
      let c = newHttpClient(userAgent = userAgent, timeout = timeoutMs)
      defer:
        c.close()
      let r = c.head(url)
      if r.code.is2xx and r.headers.hasKey("content-length"):
        return some(parseBiggestInt(r.headers["content-length"]))
    except Exception: # (httpclient is declared to raise anything)
      discard
  result.getTelling = proc(
      url: string, tick: Tick, maxBytes: int64
  ): FetchResult {.closure, raises: [].} =
    try:
      let c = newHttpClient(userAgent = userAgent, timeout = timeoutMs)
      defer:
        c.close()
      c.onProgressChanged = proc(
          total, progress, speed: BiggestInt
      ) {.closure, gcsafe, raises: [TooBig].} =
        {.cast(gcsafe).}: # (the sink is ours and runs in this thread)
          if tick != nil:
            tick(int64(progress), int64(max(total, 0)))
          checkProgress(int64(progress), maxBytes)
      let r = c.get(url)
      if r.code.is2xx:
        return FetchResult(ok: true, status: int(r.code), body: r.body)
      return FetchResult(
        ok: false, status: int(r.code), message: "the server said " & r.status
      )
    except TooBig as e:
      return FetchResult(ok: false, message: e.msg)
    except Exception: # (httpclient is declared to raise anything)
      return FetchResult(ok: false, message: getCurrentExceptionMsg())
  let telling = result.getTelling
  result.get = proc(url: string): FetchResult {.closure, raises: [].} =
    telling(url, nil, high(int64))

proc realFreeBytes*(dir: string): Option[int64] {.raises: [].} =
  ## Room left on the disk that holds `dir` (or the nearest directory above it that exists).
  when defined(posix):
    var path = dir
    while path.len > 1 and not dirExists(path):
      path = parentDir(path)
    var s: Statvfs
    if statvfs(cstring(path), s) == 0:
      return some(int64(s.f_bavail) * int64(s.f_frsize))
  none(int64)

proc realEnv*(): Env =
  ## The environment for real use: the network, the disk, and the child process that inflates zips.
  Env(
    fetcher: realFetcher(),
    freeBytes: realFreeBytes,
    inflater: inflateInChild(getAppFilename()),
  )

# --- fetching

func sourceDir*(dataDir: string, src: Source): string =
  ## Where the files of a source are kept: a directory of its own in the data directory.
  dataDir / src.name

proc fail(sink: Sink, src: Source, url, why: string): Option[string] =
  sink(DownloadEvent(kind: deFailed, source: src.name, url: url, message: why))
  none(string)

proc checkContent(src: Source, arg, body: string): string =
  ## "" if what came is what was asked for, else what is wrong with it.
  if body.len == 0:
    return "the file is empty"
  if src.zipEntry.len == 0:
    return ""
  let want = entryFor(src, arg)
  try:
    let entries = listEntries(body)
    if want notin entries:
      return "the zip has no " & want
    if entries.must(want).size == 0:
      return "the zip's " & want & " is empty"
  except ZipError as e:
    return "not a zip file (" & e.msg & ")"
  ""

proc fetchSource*(
    env: Env, sink: Sink, dataDir: string, src: Source, arg = ""
): Option[string] =
  ## The path of the source's file in the cache: already there, or fetched now.  None if it could
  ## not be had (a failed event says why).
  let dir = sourceDir(dataDir, src)
  let path = dir / fileFor(src, arg)
  try:
    if fileExists(path) and getFileSize(path) > 0:
      return some(path)
  except OSError:
    discard
  let url = urlFor(src, arg)
  sink(
    DownloadEvent(
      kind: deStarting,
      source: src.name,
      url: url,
      message: whyFor(src, arg),
      label: labelFor(src, arg),
    )
  )
  # the size, and the room
  let announced = env.fetcher.head(url)
  if announced.isSome and announced.get > src.maxBytes:
    return fail(
      sink,
      src,
      url,
      "the file is " & humanBytes(announced.get) & ", more than the " &
        humanBytes(src.maxBytes) & " allowed",
    )
  let size = if announced.isSome: announced.get else: src.maxBytes
  let need = size * spaceFactor + reserveBytes
  let free = env.freeBytes(dataDir)
  if free.isSome and free.get < need:
    return fail(
      sink,
      src,
      url,
      "not enough room on the disk: " & humanBytes(need) &
        " wanted (the file, what is made from it and " & humanBytes(reserveBytes) &
        " to spare), " & humanBytes(free.get) & " free",
    )
  # the file
  let tick = proc(done, total: int64) {.closure, raises: [].} =
    sink(
      DownloadEvent(
        kind: deProgress,
        source: src.name,
        url: url,
        bytes: done,
        total: (if total > 0: total elif announced.isSome: announced.get else: 0),
      )
    )
  let r =
    if env.fetcher.getTelling != nil:
      tick(0, 0) # (the size the server announced goes with it)
      env.fetcher.getTelling(url, tick, src.maxBytes)
    else:
      env.fetcher.get(url)
  if not r.ok:
    return fail(sink, src, url, r.message)
  if int64(r.body.len) > src.maxBytes:
    return fail(
      sink,
      src,
      url,
      "the file is " & humanBytes(int64(r.body.len)) & ", more than the " &
        humanBytes(src.maxBytes) & " allowed",
    )
  let problem = checkContent(src, arg, r.body)
  if problem.len > 0:
    return fail(sink, src, url, problem)
  try:
    createDir(dir)
    writeAtomic(path, r.body)
  except IOError, OSError:
    return
      fail(sink, src, url, "cannot write " & path & ": " & getCurrentExceptionMsg())
  sink(
    DownloadEvent(
      kind: deDownloaded,
      source: src.name,
      url: url,
      path: path,
      bytes: int64(r.body.len),
    )
  )
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

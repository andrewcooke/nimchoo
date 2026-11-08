## The log file: one line per event, appended, with rotation.  Where it is,
## and what a line looks like, are in the functions below; nothing here knows
## about any command.  A line is
##
##     2026-11-02T23:10:34Z INFO  import    duplicate  text
##     time                 level command   event      text
##
## where the command is what the user ran and the event is one of the shared
## words in vocabulary.nim.
##
## Logging must never break the work: a log that cannot be opened is disabled
## (`problem` says why, for the caller to mention once), and a write that
## fails is ignored.  A nil `Log` is a disabled log.

import std/[options, os, strutils, times]
import ../cli/catalog
export catalog
import ./vocabulary
export vocabulary.LogEvent

{.push raises: [].}

type
  Level* = enum
    lvInfo = "INFO "
    lvWarn = "WARN "
    lvError = "ERROR"

  Clock* = proc(): Time {.closure, raises: [].}

  Log* = ref object
    f: File
    now: Clock
    path*: string ## where it is
    problem*: string ## why the log is disabled ("" if it is not)

const
  defaultMaxBytes* = 5_000_000
  defaultKeep* = 3
  commandWidth = 8 ## columns of the command (longer ones push the rest along)
  eventWidth = 9 ## ... and of the event

func logPath*(nchLog, xdgState, home: Option[string]): Option[string] =
  ## Where the log goes, given the environment variables NCH_LOG and
  ## XDG_STATE_HOME and the home directory.  NCH_LOG wins, and empty switches
  ## logging off; a relative XDG_STATE_HOME is ignored (as the XDG spec says).
  if nchLog.isSome:
    return
      if nchLog.get.len > 0:
        nchLog
      else:
        none(string)
  if xdgState.isSome and xdgState.get.isAbsolute:
    return some(xdgState.get / "nch" / "nch.log")
  if home.isSome and home.get.len > 0:
    return some(home.get / ".local" / "state" / "nch" / "nch.log")
  none(string)

proc envOpt(name: string): Option[string] =
  if existsEnv(name):
    some(getEnv(name))
  else:
    none(string)

proc envLogPath*(): Option[string] =
  ## `logPath` for the real environment.
  logPath(envOpt("NCH_LOG"), envOpt("XDG_STATE_HOME"), envOpt("HOME"))

proc logLine*(
    t: Time, level: Level, command: string, event: LogEvent, text: string
): string =
  ## "2026-11-02T09:14:03Z INFO  import    duplicate  text": one line, whatever
  ## `text` holds.
  const fmt = initTimeFormat("yyyy-MM-dd'T'HH:mm:ss'Z'")
  t.utc.format(fmt) & " " & $level & " " & command.alignLeft(commandWidth) & "  " &
    ($event).alignLeft(eventWidth) & "  " & text.replace('\n', ' ').replace('\r', ' ')

proc rotate*(path: string, maxBytes = defaultMaxBytes, keep = defaultKeep) =
  ## If the log is over `maxBytes`: `path` becomes `path.1`, `.1` becomes
  ## `.2`, and so on; what would become `.keep+1` is deleted.  Best effort.
  try:
    if not fileExists(path) or getFileSize(path) <= maxBytes:
      return
    removeFile path & "." & $keep
    for i in countdown(keep - 1, 1):
      if fileExists(path & "." & $i):
        moveFile path & "." & $i, path & "." & $(i + 1)
    moveFile path, path & ".1"
  except OSError:
    discard
  except Exception: # (moveFile is declared to raise anything)
    discard

proc realClock(): Time {.raises: [].} =
  getTime()

proc openLog*(
    path: string, maxBytes = defaultMaxBytes, keep = defaultKeep, now: Clock = realClock
): Log =
  ## Open (creating it and its directory if need be) the log at `path`,
  ## rotating first.  If it cannot be opened the result is a disabled log
  ## whose `problem` says why.
  result = Log(now: now, path: path)
  try:
    createDir parentDir(path)
    rotate path, maxBytes, keep
    if not open(result.f, path, fmAppend):
      result.problem = "cannot open " & path
  except OSError, IOError:
    result.problem = "cannot open " & path & ": " & getCurrentExceptionMsg()

func enabled*(l: Log): bool =
  not l.isNil and not l.f.isNil

proc log*(l: Log, level: Level, command: Command, event: LogEvent, text: string) =
  ## Append a line.  Warnings and errors are flushed at once, the rest when
  ## the buffer fills or the log is closed.
  if not l.enabled:
    return
  try:
    l.f.write logLine(l.now(), level, $command, event, text) & "\n"
    if level != lvInfo:
      l.f.flushFile()
  except IOError:
    discard

proc close*(l: Log) =
  if not l.enabled:
    return
  try:
    l.f.close()
  except IOError:
    discard
  l.f = nil

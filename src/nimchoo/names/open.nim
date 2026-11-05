## The way into the names for a command: `openNames(g, st)` finds the cache, honours `--offline`, and has the
## downloads told in the log and on the screen.  A command that wants a name needs to know nothing of caches,
## downloads or sinks.

import std/options
import ../cache
import ../cli/common
import ../db/store
import ../download/[fetch, sinks]
import ./countries

{.push raises: [].}

proc openNames*(g: Globals, st: Store, command: string, say: proc(line: string) {.closure, raises: [].}): Option[Names] =
  ## The names for `st`, as `command` (the name the log uses).  None if there is no cache directory to keep them in.
  ## `say` is where the downloads are told on the screen (a line each).
  let cache = cacheDir()
  if cache.isNone: return none(Names)
  var names = newNames(st, dataDir(cache.get), realEnv(), fanOut(@[logSink(g.log, command), screenSink(say)]))
  names.offline = g.offline
  some(names)

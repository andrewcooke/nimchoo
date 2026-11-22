## `nch --config`: the settings in force (the database, its schema, the user, the theme, the log, the cache, the access
## model) and the variables of the environment that nch reads, with what each is for.  Part of `nch`, not a package: it
## needs the whole registry.

import std/[options, os, sequtils, strformat, strutils]
import ./core/[access, errors, globals, logfile, ruled]
import ./packages/cache/cache
import ./packages/db/store
import ./packages/fit/default
import ./packages/ui/[markup, style, units]
import ./packages/user/session
import ./packages/util/version/version
import ./registry as generated

{.push raises: [].}

proc fragmentLines*(path: string): seq[string] =
  ## What the database file has had applied, against what this program has: the fragments are the SQL that makes the
  ## tables, in the order the program applies them (`db` package).
  let program = generated.schema
  let what =
    fmt"the program has {program.len} fragments (the SQL that makes its tables)"
  if not fileExists(path):
    return @[fmt"{what}; there is no database yet"]
  var have: seq[(string, string)]
  try:
    have = appliedFragments(path)
  except StoreError as e:
    return @[fmt"{what}; the database: {e.msg}"]
  var differences: seq[string]
  for (name, sum) in have:
    let known = program.filterIt(it.name == name)
    if known.len == 0:
      differences.add fmt"{name}: only in the database (from a newer version: it will be refused)"
    elif known[0].checksum != sum:
      differences.add fmt"{name}: not the SQL this version has (made by a different version: it will be refused)"
  for f in program:
    if have.allIt(it[0] != f.name):
      differences.add fmt"{f.name}: not applied yet (it will be, when the database is opened)"
  if differences.len == 0:
    return
      @[fmt"{what}, and the database has had all of them, as this version has them"]
  @[fmt"{what}; the database has had {have.len}:"] & differences

proc userText(g: Globals, path: string): string =
  ## The user the commands work on: its name, and "(default)" if it is the default one.
  if not fileExists(path):
    return g.user.get("the default user") & " (there is no database yet)"
  var ro = g
  ro.readOnly = true
  try:
    let st = openSession(ro)
    defer:
      st.close()
    result = st.userName & (if st.isDefault: " (default)" else: "")
  except StoreError as e:
    result = e.msg

type EnvVar = tuple[name, what: string, default: Option[string], isPath: bool]

proc environment(): seq[EnvVar] =
  ## The variables of the environment that nch reads, what each is for, and what is used when it is not set.
  let home = envOpt("HOME")
  func under(p: string): Option[string] =
    (if home.isSome: some(home.get / p) else: none(string))

  @[
    ("NCH_DB", "the database file (`--db` comes first)", some(defaultDbPath()), true),
    (
      "NCH_LOG",
      "the log file; set and empty: no log",
      logPath(none(string), envOpt("XDG_STATE_HOME"), home),
      true,
    ),
    (
      "NCH_CACHE",
      "the cache directory",
      cachePath(none(string), envOpt("XDG_CACHE_HOME"), home),
      true,
    ),
    (
      "XDG_DATA_HOME",
      "where the database goes (in `nch/`) when NCH_DB is not set",
      under(".local/share"),
      true,
    ),
    (
      "XDG_STATE_HOME",
      "where the log goes (in `nch/`) when NCH_LOG is not set",
      under(".local/state"),
      true,
    ),
    (
      "XDG_CACHE_HOME",
      "where the cache goes (in `nch/`) when NCH_CACHE is not set",
      under(".cache"),
      true,
    ),
    (
      "NO_COLOR",
      "set to anything: no colour (a convention many programs follow); not set: colour on a terminal",
      none(string),
      false,
    ),
    ("NCH_THEME", "the theme, when `--theme` is not given", none(string), false),
    (
      "COLORFGBG",
      "set by some terminals (the numbers of the text and background colours): whether the background is light, to choose the light or dark theme when nothing else does",
      none(string),
      false,
    ),
  ]

proc environmentLines(width: int): seq[Line] =
  ## The variables of the environment: the value of each (or what is used when it is not set, "(default)"), and what
  ## it is for.
  var rows: seq[seq[Line]]
  for v in environment():
    let given = envOpt(v.name)
    let value =
      if given.isSome:
        (
          if v.isPath and given.get.len > 0: ~"<file {given.get}>"
          else: plain(given.get)
        )
      elif v.default.isSome:
        ~"<file {v.default.get}> (default)"
      else:
        plain("not set (default)")
    rows.add @[plain(v.name), value, plain(v.what)]
  ruled(@["variable", "value", "what it is for"], rows, width)

proc configLines*(g: Globals, width: int, commands: seq[string]): seq[Line] =
  ## The settings in force, and where each came from (a path in `file`), as a table without headings; then the
  ## variables of the environment.
  var rows: seq[seq[Line]]
  func row(label: string, value: Line): seq[Line] =
    @[plain(label), value]

  func row(label, value: string): seq[Line] =
    row(label, plain(value))

  func pathOr(path: Option[string], otherwise: string): Line =
    if path.isSome:
      ~"<file {path.get}>"
    else:
      plain(otherwise)
  rows.add row("version", versionString)
  let (path, origin) = dbPathAndSource(g.dbPath)
  let source =
    case origin
    of dsOption: "--db"
    of dsEnvironment: "$NCH_DB"
    of dsDefault: "the default"
  var state = "not made yet"
  try:
    if fileExists(path):
      state = humanBytes(getFileSize(path))
  except OSError:
    state = "cannot be read"
  rows.add row("database", ~"<file {path}>  ({source}; {state})")
  rows.add row("schema", fragmentLines(path).join("\n"))
  rows.add row("user", userText(g, path))
  rows.add row("offline", if g.offline: "yes (`--offline`)" else: "no")
  rows.add row("FIT profile", profileInUse())
  rows.add row(
    "theme",
    if g.theme.name.len > 0:
      fmt"{g.theme.name}  ({g.theme.origin})"
    else:
      "none: the terminal's own text",
  )
  let log = envLogPath()
  rows.add row("log", pathOr(log, "off (NCH_LOG is empty)"))
  let cache = cacheDir()
  rows.add row("cache", pathOr(cache, "none (no HOME)"))
  rows.add row(
    "access",
    case g.access.mode
    of amEnforce: "enforced: a package that touches the table of another is refused"
    of amOff: "off"
    ,
  )
  rows.add row("commands", commands.join(", "))
  result = ruled(@["", ""], rows, width)
  result.add plain("")
  result.add environmentLines(width)

## The cache directory, where commands that make files (maps, exports) put
## them, and what such files are called.  A file is named after the command
## line that made it, so the same request finds the same files:
##
##     heatmap--key-ab12cd--style-lines.geojson
##
## (the command, then each option as `--name-value`, in the order of the option
## names).  What may appear in a name is limited, and anything else is refused
## rather than escaped, so a name is always a plain file name that can be put in
## a URL.  The cache directory has two parts, `user/` (made by commands) and `system/` (unpacked
## from the program), and keeps the server's token at its top.  Pure functions: no files are
## touched here.

import std/[algorithm, options, os, sequtils, strutils]

{.push raises: [].}

const
  extensions* = ["html", "geojson", "csv"]          ## what may be written, and served
  maxNameLength = 200

func isNameChar(c: char): bool = c in {'a' .. 'z', '0' .. '9'}
func isValueChar(c: char): bool = c in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '.', '_', ',', '-'}

func isCommandName*(s: string): bool =
  ## "heatmap": lower case letters and digits, not empty.
  s.len > 0 and s.allIt(it.isNameChar)

func isOptionName*(s: string): bool =
  isCommandName(s)

func isOptionValue*(s: string): bool =
  ## "ab12cd", "lines", "5.5": letters, digits and . _ , -, not empty, and no "--"
  ## (which would end the value).
  s.len > 0 and s.allIt(it.isValueChar) and "--" notin s

func fileStem*(command: string, options: openArray[(string, string)]): Option[string] =
  ## The name, without extension, for a command and its options; none if any of
  ## them is not allowed, an option is repeated, or the name would be too long.
  if not isCommandName(command): return none(string)
  var sorted = @options
  sorted.sort do (a, b: (string, string)) -> int: cmp(a[0], b[0])
  var name = command
  var last = ""
  for (k, v) in sorted:
    if not isOptionName(k) or not isOptionValue(v) or k == last: return none(string)
    last = k
    name.add "--" & k & "-" & v
  if name.len > maxNameLength: none(string) else: some(name)

func parseStem*(stem: string): Option[(string, seq[(string, string)])] =
  ## The inverse of `fileStem`: "heatmap--key-ab12--style-lines" is the command
  ## "heatmap" and the options [("key", "ab12"), ("style", "lines")].  None if it is not
  ## a name `fileStem` would make.
  let parts = stem.split("--")
  if not isCommandName(parts[0]): return none((string, seq[(string, string)]))
  var options: seq[(string, string)]
  for p in parts[1 .. ^1]:
    let dash = p.find('-')
    if dash < 1 or not isOptionName(p[0 ..< dash]) or not isOptionValue(p[dash + 1 .. ^1]):
      return none((string, seq[(string, string)]))
    options.add (p[0 ..< dash], p[dash + 1 .. ^1])
  some((parts[0], options))

func userDir*(dir: string): string =
  ## Where commands put what they make (maps, charts, pages): a part of the cache directory `dir`.
  ## The server serves nothing else.
  dir / "user"

func systemDir*(dir: string): string =
  ## Where what is unpacked from the program goes (the profile, the licence notice, the page
  ## templates): the other part of the cache directory.  Nothing here is made by a command, and all
  ## of it can be deleted: it is unpacked again.
  dir / "system"

func dataDir*(dir: string): string =
  ## Where what is downloaded goes (the country files for names): the third part of the cache directory.
  ## Not made by a command and not unpacked from the program, so `empty --cache` leaves it; `empty --downloads`
  ## deletes it.
  dir / "data"

func cacheFile*(dir, stem, extension: string): Option[string] =
  ## The path of a file in the cache directory; none for an extension not allowed.
  if extension in extensions: some(dir / (stem & "." & extension)) else: none(string)

func isCacheFileName*(name: string): bool =
  ## Whether `name` (as it arrives in a URL) is the name of a file this module
  ## would make: a plain file name, with an allowed extension.  The server serves
  ## nothing else.
  let (dir, base, ext) = splitFile(name)
  if dir.len > 0 or ext.len < 2 or ext[1 .. ^1] notin extensions: return false
  if name.len > maxNameLength + 8: return false
  let parts = base.split("--")
  if not isCommandName(parts[0]): return false
  for p in parts[1 .. ^1]:
    let dash = p.find('-')
    if dash < 1 or not isOptionName(p[0 ..< dash]) or not isOptionValue(p[dash + 1 .. ^1]):
      return false
  true

func cachePath*(nchCache, xdgCache, home: Option[string]): Option[string] =
  ## The cache directory, given $NCH_CACHE, $XDG_CACHE_HOME and the home
  ## directory.  $NCH_CACHE wins; a relative $XDG_CACHE_HOME is ignored (as the XDG
  ## spec says); none if nothing is known.
  if nchCache.isSome and nchCache.get.len > 0: return nchCache
  if xdgCache.isSome and xdgCache.get.isAbsolute: return some(xdgCache.get / "nch")
  if home.isSome and home.get.len > 0: return some(home.get / ".cache" / "nch")
  none(string)

proc envOpt(name: string): Option[string] =
  if existsEnv(name): some(getEnv(name)) else: none(string)

proc cacheDir*(): Option[string] =
  ## `cachePath` for the real environment.
  cachePath(envOpt("NCH_CACHE"), envOpt("XDG_CACHE_HOME"), envOpt("HOME"))

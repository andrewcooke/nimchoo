## The cache directory, where commands that make files (maps, exports) put
## them, and what such files are called.  A file is named by the command and its options, spelt out
## (`ff-default-hourly.csv`), and is made again on every request: a view shows the data as they are now.  A map's names end in
## a key of what the file was made from (`map-activities-routes-3f9a0c1d5e7b2a46.geojson`, see `map/command`), which is only
## a part of the options as far as this module is concerned.
##
## A name is always a plain file name that can be put in a URL.  The cache directory has two parts, `user/` (made by commands) and `system/` (unpacked
## from the program), and keeps the server's token at its top.  Pure functions: no files are
## touched here.

import std/[options, os, sequtils, strutils]

{.push raises: [].}

const
  extensions* = ["html", "geojson", "csv"] ## what may be written, and served
  maxNameLength = 200

func isNameChar(c: char): bool =
  c in {'a' .. 'z', '0' .. '9'}
func isValueChar(c: char): bool =
  c in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '.', '_', ',', '-'}

func isCommandName*(s: string): bool =
  ## "ff": lower case letters and digits, not empty.
  s.len > 0 and s.allIt(it.isNameChar)

func isOptionValue*(s: string): bool =
  ## "ab12cd", "lines", "5.5": letters, digits and . _ , -, not empty, and no "--": what a value in an address may be
  ## (a name of a model, a day, a number, a hash).
  s.len > 0 and s.allIt(it.isValueChar) and "--" notin s

func isFileStem*(stem: string): bool =
  ## "map-routes-climbs": a command name, a hyphen, and the options spelt out (letters, digits and . _ , -, no "--").
  let dash = stem.find('-')
  dash > 0 and isCommandName(stem[0 ..< dash]) and isOptionValue(stem[dash + 1 .. ^1]) and
    "--" notin stem and not stem.endsWith('-')

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
  ## Not made by a command and not unpacked from the program, so `cache --delete geojson` (and csv, html) leave it;
  ## `cache --delete downloads` deletes it.
  dir / "data"

func cacheFile*(dir, stem, extension: string): Option[string] =
  ## The path of a file in the cache directory; none for an extension not allowed.
  if extension in extensions:
    some(dir / (stem & "." & extension))
  else:
    none(string)

func isCacheFileName*(name: string): bool =
  ## Whether `name` (as it arrives in a URL) is the name of a file this module
  ## would make: a plain file name, with an allowed extension.  The server serves
  ## nothing else.
  let (dir, base, ext) = splitFile(name)
  if dir.len > 0 or ext.len < 2 or ext[1 .. ^1] notin extensions:
    return false
  if name.len > maxNameLength + 8:
    return false
  isFileStem(base)

func cachePath*(nchCache, xdgCache, home: Option[string]): Option[string] =
  ## The cache directory, given $NCH_CACHE, $XDG_CACHE_HOME and the home
  ## directory.  $NCH_CACHE wins; a relative $XDG_CACHE_HOME is ignored (as the XDG
  ## spec says); none if nothing is known.
  if nchCache.isSome and nchCache.get.len > 0:
    return nchCache
  if xdgCache.isSome and xdgCache.get.isAbsolute:
    return some(xdgCache.get / "nch")
  if home.isSome and home.get.len > 0:
    return some(home.get / ".cache" / "nch")
  none(string)

proc envOpt(name: string): Option[string] =
  if existsEnv(name):
    some(getEnv(name))
  else:
    none(string)

proc cacheDir*(): Option[string] =
  ## `cachePath` for the real environment.
  cachePath(envOpt("NCH_CACHE"), envOpt("XDG_CACHE_HOME"), envOpt("HOME"))

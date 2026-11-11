## The cache directory, where commands that make files (maps, exports) put
## them, and what such files are called.  A file is named after the request that
## made it, so the same request finds the same files: the command and a hash of
## the request (the whole pinned address, which is always at hand, so the name does
## not need to say what it holds):
##
##     ff-lusab-babad-fuzoh.csv
##
## A name is always a plain file name that can be put in a URL.  The cache directory has two parts, `user/` (made by commands) and `system/` (unpacked
## from the program), and keeps the server's token at its top.  Pure functions: no files are
## touched here.

import std/[options, os, parseutils, sequtils, strutils]
import ../util/hashing/hashing
import ../text/proquint/proquint

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

func requestStem*(command, request: string): Option[string] =
  ## The name, without extension, for what `command` makes for a `request` (the text that says exactly what is wanted):
  ## the command, a hyphen and 48 bits of the request's hash as pronounceable words: "map-lusab-babad-fuzoh".  The same
  ## request gives the same name.  None if the command is not a command name.
  if not isCommandName(command):
    return none(string)
  let hex = sha256Hex(request)
  var bytes: seq[byte]
  for i in 0 ..< 6:
    var v = 0
    discard parseHex(hex[2 * i ..< 2 * i + 2], v)
    bytes.add byte(v)
  some(command & "-" & proquint(bytes))

func inputsKey*(code: string, inputs: openArray[(string, string)]): string =
  ## The key of everything a cached file was made from, besides the request that names it: `code` says the version of
  ## the program and of the method (a change of either makes every file stale), and each input is the key its owner
  ## gives to the data it supplied, as (owner, key).  The file records this key; a file whose key differs from the
  ## one worked out now is made again, in place.  Declaring the inputs here, with the owner's name in the key, is what
  ## stops a new input from being forgotten: a file is fresh only if every declared input is unchanged.
  var text = "code=" & code & "\n"
  for (owner, key) in inputs:
    text.add owner & "=" & key & "\n"
  sha256Hex(text)[0 ..< 16]

func isRequestStem(base: string): bool =
  ## "map-lusab-babad-fuzoh": a command name, a hyphen, and a proquint.
  let dash = base.find('-')
  dash > 0 and isCommandName(base[0 ..< dash]) and isProquint(base[dash + 1 .. ^1])

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
  isRequestStem(base)

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

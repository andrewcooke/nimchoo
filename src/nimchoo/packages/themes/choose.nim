## Which theme is in force (see package.nim): `chooseName` decides from what is given, `loadTheme` reads the theme.

import std/[options, os, strformat, strutils]
import ../../core/[errors, theme]
import ../bundle/unpack
import ../cache/cache
import ../ui/style

{.push raises: [].}

func bundlesOf(themes: openArray[tuple[name, text: string]]): seq[Bundle] =
  for t in themes:
    result.add Bundle(name: "themes/" & t.name & ".txt", data: t.text)

const
  builtIn* = bundlesOf(builtInThemes)
    ## the themes the program carries (`ui/style.nim`), as they are unpacked
  fallback* = "dark"
    ## the theme when nothing says which, and when the one chosen cannot be used
  currentLink* = ".current" ## the link in `system/themes/` that names the theme in force

type
  Given* = object ## what may say which theme: none for what is not given
    flag*, env*: Option[string] ## `--theme`, `$NCH_THEME`
    link*: Option[string] ## where `.current` points
    colorFgBg*: Option[string] ## `$COLORFGBG`

  Choice* = object
    name*: string
    origin*: string ## what chose it

func themesDir*(cache: string): string =
  ## Where the themes are, in the cache directory `cache`.
  systemDir(cache) / "themes"

func lightBackground*(colorFgBg: string): Option[bool] =
  ## Whether `$COLORFGBG` ("15;0", "0;default;15": the last part is the background) says the background is light; none
  ## if it does not say.  (Of the sixteen colours, 7 and 9 to 15 are light.)
  try:
    let bg = parseInt(colorFgBg.split(';')[^1])
    if bg in 0 .. 15:
      return some(bg == 7 or bg >= 9)
  except ValueError:
    discard
  none(bool)

func linkName*(target: string): Option[string] =
  ## The theme a `.current` that points to `target` names: `NAME.txt` in the same directory.
  let (dir, name, ext) = splitFile(target)
  if dir.len == 0 and ext == ".txt" and name.len > 0:
    some(name)
  else:
    none(string)

func chooseName*(g: Given): Choice {.raises: [ThemeError].} =
  ## The theme that what is given chooses, the first of `--theme`, `$NCH_THEME`, `.current` and `$COLORFGBG`; else the
  ## fallback.  A link that does not name a theme is a `ThemeError`.
  if g.flag.isSome:
    return Choice(name: g.flag.get, origin: "--theme")
  if g.env.isSome:
    return Choice(name: g.env.get, origin: "$NCH_THEME")
  if g.link.isSome:
    let name = linkName(g.link.get)
    if name.isNone:
      raiseTheme(
        fmt"{currentLink} points to '{g.link.get}', not to a theme in its directory (NAME.txt)"
      )
    return Choice(name: name.get, origin: fmt"system/themes/{currentLink}")
  if g.colorFgBg.isSome:
    let light = lightBackground(g.colorFgBg.get)
    if light.isSome:
      return Choice(
        name: (if light.get: "light" else: "dark"),
        origin: fmt"$COLORFGBG={g.colorFgBg.get}",
      )
  Choice(name: fallback, origin: "the default")

func isThemeName*(s: string): bool =
  ## A name of a theme: letters, digits, hyphens and underscores (it is the name of a file).
  s.len > 0 and s.allCharsInSet({'a' .. 'z', 'A' .. 'Z', '0' .. '9', '-', '_'})

proc themeText(cache, name: string): string {.raises: [ThemeError].} =
  ## The text of the theme `name`: the built-in one (as unpacked, or as edited), or the file of that name.
  for b in builtIn:
    if b.name == fmt"themes/{name}.txt":
      return resolve(cache, b).data
  if not isThemeName(name):
    raiseTheme(fmt"'{name}' is not a name of a theme")
  let path = themesDir(cache) / fmt"{name}.txt"
  if cache.len == 0 or not fileExists(path):
    raiseTheme(fmt"there is no theme '{name}' (no {path})")
  try:
    readFile(path)
  except IOError as e:
    raiseTheme(fmt"cannot read {path}: {e.msg}")

proc builtInTheme(name: string): Theme =
  ## A theme the program carries, as it carries it.
  for b in builtIn:
    if b.name == fmt"themes/{name}.txt":
      try:
        result = parseTheme(b.data)
      except ThemeError as e:
        raiseAssert fmt"the built-in theme {name}: {e.msg}" # (tested)
      result.name = name
      return
  raiseAssert fmt"no built-in theme {name}"

proc given(cache: string, flag: Option[string]): Given =
  ## What the command line, the environment and the cache say.
  result.flag = flag
  for (field, variable) in [
    (addr result.env, "NCH_THEME"), (addr result.colorFgBg, "COLORFGBG")
  ]:
    let v = getEnv(variable)
    if v.len > 0:
      field[] = some(v)
  if cache.len > 0:
    let link = themesDir(cache) / currentLink
    try:
      if symlinkExists(link):
        result.link = some(expandSymlink(link))
    except OSError:
      discard

proc loadTheme*(
    cache: string, flag: Option[string]
): tuple[theme: Theme, warning: Option[string]] =
  ## The theme in force, given the cache directory (""; none) and `--theme` (none if not given), with the built-in themes
  ## unpacked to the cache; if the one chosen cannot be used, the fallback and why.
  for b in builtIn:
    discard
      resolve(cache, b) # (so that they are there to be seen, copied and linked to)
  let g = given(cache, flag)
  var name = ""
  try:
    let choice = chooseName(g)
    name = choice.name
    result.theme = parseTheme(themeText(cache, choice.name))
    result.theme.name = choice.name
    result.theme.origin = choice.origin
  except ThemeError as e:
    let which =
      if name.len > 0:
        fmt"the theme {name}"
      else:
        "the theme"
    result.theme = builtInTheme(fallback)
    result.theme.origin = "the fallback"
    result.warning = some(fmt"{which}: {e.msg} (using the built-in {fallback})")

proc themeNames*(cache: string): seq[string] =
  ## The themes there are: the built-in ones, and the files `NAME.txt` in `system/themes/`.
  for b in builtIn:
    result.add splitFile(b.name).name
  if cache.len == 0:
    return
  try:
    for kind, path in walkDir(themesDir(cache)):
      let (_, name, ext) = splitFile(path)
      if kind in {pcFile, pcLinkToFile} and ext == ".txt" and isThemeName(name) and
          name notin result:
        result.add name
  except OSError:
    discard

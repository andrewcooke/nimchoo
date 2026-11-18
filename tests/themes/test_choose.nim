import std/[options, os, strutils, tables, unittest]
import nimchoo/core/[errors, theme]
import nimchoo/packages/themes/choose

let cache = getTempDir() / "nch-test-themes"

proc fresh() =
  removeDir(cache)
  createDir(cache)

suite "themes: which one is chosen":
  test "the built-in themes can be read, and have the styles the program uses":
    for b in builtIn:
      let t = parseTheme(b.data)
      for name in ["default", "em", "hide", "good", "bad", "warn", "select"]:
        check name in t.styles

  test "COLORFGBG says light for a light background, dark for a dark one, nothing otherwise":
    check lightBackground("0;15") == some(true)
    check lightBackground("0;7") == some(true)
    check lightBackground("15;0") == some(false)
    check lightBackground("15;default;8") == some(false)
    check lightBackground("15;default") == none(bool)
    check lightBackground("") == none(bool)
    check lightBackground("0;99") == none(bool)

  test "the link names a theme in its own directory":
    check linkName("light.theme") == some("light")
    check linkName("/etc/passwd") == none(string)
    check linkName("../light.theme") == none(string)
    check linkName("light") == none(string)

  test "the first that is given chooses":
    let all = Given(
      flag: some("a"), env: some("b"), link: some("c.theme"), colorFgBg: some("0;15")
    )
    check chooseName(all) == Choice(name: "a", origin: "--theme")
    var g = all
    g.flag = none(string)
    check chooseName(g) == Choice(name: "b", origin: "$NCH_THEME")
    g.env = none(string)
    check chooseName(g) == Choice(name: "c", origin: "system/themes/.current")
    g.link = none(string)
    check chooseName(g) == Choice(name: "light", origin: "$COLORFGBG=0;15")
    g.colorFgBg = some("garbage")
    check chooseName(g) == Choice(name: "dark", origin: "the default")
    g.colorFgBg = none(string)
    check chooseName(g) == Choice(name: "dark", origin: "the default")

  test "a link that names no theme is refused":
    expect ThemeError:
      discard chooseName(Given(link: some("/etc/passwd")))

suite "themes: reading the one chosen":
  test "the built-in themes are unpacked, and one is used as it is in the cache":
    fresh()
    let r = loadTheme(cache, some("light"))
    check r.warning.isNone
    check r.theme.name == "light"
    check fileExists(themesDir(cache) / "dark.theme")
    check fileExists(themesDir(cache) / "light.theme")
    writeFile(themesDir(cache) / "light.theme", "default\nem underline=yes\n")
    let edited = loadTheme(cache, some("light"))
    check edited.theme.styles["em"].underline == some(true)
    check "good" notin edited.theme.styles

  test "a theme of the author's own is a file in the directory":
    fresh()
    discard loadTheme(cache, none(string))
    writeFile(themesDir(cache) / "mine.theme", "em fg=#123456\n")
    let r = loadTheme(cache, some("mine"))
    check r.warning.isNone
    check r.theme.name == "mine"
    check r.theme.origin == "--theme"
    check "mine" in themeNames(cache)
    check themeNames(cache)[0 .. 1] == @["dark", "light"]

  test "a theme that cannot be used gives the fallback and a warning":
    fresh()
    for (name, text, says) in [
      ("missing", "", "there is no theme 'missing'"),
      ("broken", "em fg=pink\n", "line 1: 'pink' is not a colour"),
      ("../x", "", "'../x' is not a name of a theme"),
    ]:
      if text.len > 0:
        createDir(themesDir(cache))
        writeFile(themesDir(cache) / (name & ".theme"), text)
      let r = loadTheme(cache, some(name))
      check r.theme.name == fallback
      check r.theme.origin == "the fallback"
      check r.warning.isSome
      check says in r.warning.get

  test "without a cache, the built-in themes are still there":
    let r = loadTheme("", some("light"))
    check r.warning.isNone
    check r.theme.name == "light"
    check "good" in r.theme.styles

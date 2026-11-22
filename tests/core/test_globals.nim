import std/[os, sequtils, strutils, unittest]
import nimchoo/core/[globals, line, theme]

suite "globals: what is said, in the theme":
  test "without colour, or with a default that changes nothing, the text is as it is":
    let plain = Globals(theme: parseTheme("default fg=white"))
    check plain.inTheme(osOut, "a\nb\n") == "a\nb\n"
    var g = Globals(theme: parseTheme("em weight=bold"))
    g.colour[osOut] = true
    check g.inTheme(osOut, "a\nb\n") == "a\nb\n"

  test "in colour, each line is in the default look, and ends with a reset":
    var g = Globals(theme: parseTheme("default fg=white"))
    g.colour[osErr] = true
    check g.inTheme(osErr, "a\n\nb\n") == "\e[37ma\e[0m\n\n\e[37mb\e[0m\n"
    check g.inTheme(osOut, "a") == "a" # (stdout is not in colour)

  test "the lines of a table are drawn in the line style, even when default changes nothing":
    var g = Globals(theme: parseTheme("hide fg=bright-black"))
    g.colour[osOut] = true
    check g.inTheme(osOut, "a │ b") == "a \e[90m│\e[0m b"
    var d = Globals(theme: parseTheme("default fg=white\nhide fg=bright-black"))
    d.colour[osOut] = true
    check d.inTheme(osOut, "a│") == "\e[37ma\e[0m\e[90m│\e[0m"

  test "a backtick in a text is a character like any other: only a code span of a Line is typed":
    var g = Globals(theme: parseTheme("code fg=blue"))
    g.colour[osOut] = true
    check g.inTheme(osOut, "see `nch climbs` now") == "see `nch climbs` now"
    check g.inTheme(osOut, "see `nch\nclimbs` now") == "see `nch\nclimbs` now"

suite "globals: nothing writes to the terminal behind the theme's back":
  test "only the low-level writers and the output for programs use stdout and stderr themselves":
    # (everything a person reads goes through `g.say`, `g.show` or `g.inTheme`, so that it is in the theme)
    let allowed = [
      "core/globals.nim", # (`say` itself)
      "completion.nim", # (the completion script and the words offered: for the shell)
      "ui/live.nim", # (the live display: its lines are drawn in the theme)
      "ui/interrupt.nim", # (a newline after Ctrl-C)
      "util/zip/zipchild.nim", # (a child process's report to its parent)
      "importer/batch.nim", # (the profiling report, for developers)
      "fit/command.nim", # (its lines go through `inTheme`)
    ]
    var found: seq[string]
    for path in walkDirRec(currentSourcePath().parentDir.parentDir.parentDir / "src"):
      if not path.endsWith(".nim") or allowed.anyIt(path.endsWith(it)):
        continue
      for n, line in readFile(path).splitLines.toSeq:
        let code = line.strip
        if code.startsWith("#"):
          continue
        if "stdout.say" in code or "stderr.say" in code or "stdout.write" in code or
            "stderr.write" in code or code.startsWith("echo "):
          found.add path & ":" & $(n + 1)
    check found.len == 0
    if found.len > 0:
      echo found.join("\n")

suite "globals: messages on one line":
  test "the lines of a message from below are joined, blank ones left out":
    check oneLine("Permission denied\nAdditional info: /x/\n") ==
      "Permission denied; Additional info: /x/"
    check oneLine("one line") == "one line"

suite "globals: warnings and what was done":
  test "each has its prefix and its style, on one line":
    check warnLine("a\nb").text == "warning: a; b" and
      $warnLine("x")[0].styles[0] == "warn"
    check doneLine(@[span("3", "select"), span(" of 5")]).text == "done: 3 of 5"

  test "a message from a Line is all in its style, its literal text keeps the backticks":
    let m = warnLine(@[span("use "), span("nch log", "code")])
    check m.text == "warning: use nch log"
    check m.plainText == "warning: use `nch log`"
    check m.allIt(($it.styles[0]) == "warn")
    check m[^1].isCode
    check warnLine(@[span("in "), span("/a\nb", "code")]).text == "warning: in /a; b"

  test "no other code writes the prefixes by hand: they come from warnLine and doneLine":
    var found: seq[string]
    let top = currentSourcePath().parentDir.parentDir.parentDir / "src"
    for path in walkDirRec(top):
      if not path.endsWith(".nim") or path.endsWith("core/globals.nim") or
          path.endsWith("registry.nim"):
        continue
      for i, whole in readFile(path).splitLines.toSeq:
        let l = whole.split("##")[0] # (a comment may quote an example)
        for prefix in [
          "\"note: ", "\"warning: ", "\"done: ", "fmt\"note: ", "fmt\"warning: ",
          "fmt\"done: ",
        ]:
          if prefix in l:
            found.add path.relativePath(top) & ":" & $(i + 1)
    check found.len == 0
    if found.len > 0:
      echo "prefixes written by hand: ", found.join(", ")

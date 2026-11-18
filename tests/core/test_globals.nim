import std/[os, sequtils, strutils, unittest]
import nimchoo/core/[globals, theme]

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

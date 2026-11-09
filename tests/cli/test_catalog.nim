import std/[algorithm, options, strutils, unittest]
import nimchoo/cli/catalog
import nimchoo/serve/request

suite "commands: the one list":
  test "a name finds its command, and only a command's name does":
    for c in Command:
      check parseCommand($c) == some(c)
    for bad in ["", "import", "user", "landmark", "Map", "map ", "heatmap", "help"]:
      check parseCommand(bad).isNone
  test "the usage list has a line for every command, with its summary":
    let text = commandList([("fit", "reads a FIT file")])
    for c in Command:
      check summaries[c].len > 0
      check text.contains("  " & $c & " ")
      check text.contains(summaries[c])
    check text.contains("  fit ") and text.contains("reads a FIT file")
    check text.countLines == ord(high(Command)) + 3
      # (a line each, the other one, and the end)
    let lines = text.splitLines
    check lines[0 ..< ^1] == sorted(lines[0 ..< ^1]) # (by name)
  test "the commands the web server may run are commands":
    for rule in commandRules:
      check parseCommand(rule.name).isSome

import std/[options, strutils, unittest]
import nimchoo/cli/catalog
import nimchoo/serve/request

suite "commands: the one list":
  test "a name finds its command, and only a command's name does":
    for c in Command:
      check parseCommand($c) == some(c)
    for bad in ["", "import", "user", "landmark", "Map", "map ", "heatmap", "help"]:
      check parseCommand(bad).isNone
  test "the usage list has a line for every command, with its summary":
    let text = commandList()
    for c in Command:
      check summaries[c].len > 0
      check text.contains("  " & $c & " ")
      check text.contains(summaries[c])
    check text.countLines == ord(high(Command)) + 2 # (a line each, and the end)
  test "the commands the web server may run are commands":
    for rule in commandRules:
      check parseCommand(rule.name).isSome

## The options every command with web pages takes (`--worker`, `--web` and what goes with it):
## parsed and described in one place, so that the commands cannot differ.  Pure.

import std/strutils
import ../packages/util/args/args
import ./request

{.push raises: [].}

type WebArgs* = object
  worker*: bool ## for programs: make the files, print the page's path, then the data's
  enabled*: bool ## `--web`: serve the page on localhost and open it in the browser
  noOpen*: bool ## ... but do not open the browser
  newToken*: bool ## ... with a new secret token (the old bookmarks stop working)
  port*: int ## ... on this port (0: any free one)

func initWebArgs*(): WebArgs =
  ## The defaults: the default port, the rest off.
  WebArgs(port: defaultPort)

proc takePort*(name, value: string, port: var int): string =
  ## The value of `--port`: a port number ("" if it is one, else what is wrong).
  var n = 0
  if not parseIntIn(value, 0, 65535, n):
    return valueIs(name, "a port number, 0 to 65535", value)
  port = n
  ""

template webOptions*(P: typedesc, field: untyped): seq[Opt[P]] =
  ## The web options as options of a command whose `P` holds them in `field` (a `WebArgs`).
  @[
    custom(P, ["--worker"], false, (p.field.worker = true; "")),
    custom(P, ["--web"], false, (p.field.enabled = true; "")),
    custom(P, ["--no-open"], false, (p.field.noOpen = true; "")),
    custom(P, ["--new-token"], false, (p.field.newToken = true; "")),
    custom(P, ["--port"], true, takePort(name, value, p.field.port)),
  ]

func webProblem*(w: WebArgs): string =
  ## What is wrong with the combination of web options ("" if nothing).
  if w.enabled and w.worker:
    return "--web and --worker cannot be used together"
  if not w.enabled and (w.noOpen or w.newToken or w.port != defaultPort):
    return "--no-open, --new-token and --port go with --web"

func webUsage*(page, data: string, width = 19): string =
  ## The lines of a command's help for the web options: `page` is what is shown ("the heat
  ## map"), `data` the file it is drawn from ("GeoJSON"); the descriptions start in column `width`.
  let pad = " ".repeat(width)
  proc line(option, text: string): string =
    ("  " & option).alignLeft(width) & text

  line(
    "--worker", "for programs: also make the web page, and print its path, then the\n"
  ) & pad & "path of the " & data & " file, and nothing else\n" &
    line(
      "--web",
      "show " & page & " in the browser: make the files, serve them on localhost\n",
    ) & pad & "(this computer only) and open the address; Ctrl-C stops it\n" &
    line(
      "--port N",
      "the port for --web (default " & $defaultPort &
        ", the keypad digits of \"mchoo\"; 0:\n",
    ) & pad & "any free one)\n" &
    line("--no-open", "with --web: print the address but do not open the browser\n") &
    line(
      "--new-token",
      "with --web: make a new secret (old bookmarks stop working; the secret\n",
    ) & pad & "is kept in the cache directory, readable only by you)\n"

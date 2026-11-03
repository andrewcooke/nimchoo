## The options every command with web pages takes (`--worker`, `--web` and what goes with it):
## parsed and described in one place, so that the commands cannot differ.  Pure.

import std/strutils
import ./request

{.push raises: [].}

type WebArgs* = object
  worker*: bool         ## for programs: make the files, print the page's path, then the data's
  enabled*: bool        ## `--web`: serve the page on localhost and open it in the browser
  noOpen*: bool         ## ... but do not open the browser
  newToken*: bool       ## ... with a new secret token (the old bookmarks stop working)
  port*: int            ## ... on this port (0: any free one)

func initWebArgs*(): WebArgs =
  WebArgs(port: defaultPort)

proc takeWebOption*(args: seq[string], i: var int, w: var WebArgs, problem: var string): bool =
  ## If `args[i]` is one of the web options, take it (and its value, moving `i` to it) and
  ## return true; `problem` says what is wrong with it, if anything.
  case args[i]
  of "--worker": w.worker = true
  of "--web": w.enabled = true
  of "--no-open": w.noOpen = true
  of "--new-token": w.newToken = true
  of "--port":
    inc i
    if i >= args.len:
      problem = "--port needs a value"
      return true
    var n = -1
    try:
      n = parseInt(args[i])
    except ValueError:
      discard
    if n < 0 or n > 65535:
      problem = "--port is a port number, 0 to 65535 (not '" & args[i] & "')"
    w.port = n
  else: return false
  true

func webProblem*(w: WebArgs): string =
  ## What is wrong with the combination of web options ("" if nothing).
  if w.enabled and w.worker: return "--web and --worker cannot be used together"
  if not w.enabled and (w.noOpen or w.newToken or w.port != defaultPort):
    return "--no-open, --new-token and --port go with --web"

func webUsage*(page, data: string, width = 19): string =
  ## The lines of a command's help for the web options: `page` is what is shown ("the heat
  ## map"), `data` the file it is drawn from ("GeoJSON"); the descriptions start in column `width`.
  let pad = " ".repeat(width)
  proc line(option, text: string): string = ("  " & option).alignLeft(width) & text
  line("--worker", "for programs: also make the web page, and print its path, then the\n") &
  pad & "path of the " & data & " file, and nothing else\n" &
  line("--web", "show " & page & " in the browser: make the files, serve them on localhost\n") &
  pad & "(this computer only) and open the address; Ctrl-C stops it\n" &
  line("--port N", "the port for --web (default " & $defaultPort & ", the keypad digits of \"mchoo\"; 0:\n") &
  pad & "any free one)\n" &
  line("--no-open", "with --web: print the address but do not open the browser\n") &
  line("--new-token", "with --web: make a new secret (old bookmarks stop working; the secret\n") &
  pad & "is kept in the cache directory, readable only by you)\n"

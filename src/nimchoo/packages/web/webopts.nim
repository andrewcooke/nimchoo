## The options every command with web pages takes (`--file`, `--worker`, and `--port`, `--no-open` and `--new-token`
## for serving, which is what the command does when it is not told otherwise): parsed and described in one place, so
## that the commands cannot differ.  Pure.

import ../util/args/args
import ./request

{.push raises: [].}

type
  WebArgs* = object
    ## The web options as they are read (a builder: `webMode` turns them into a `WebMode` or says what is wrong).
    worker*: bool ## for programs: make the files, print the page's path, then the data's
    file*: bool ## `--file`: make the file and print its path, serve nothing
    noOpen*: bool ## serving, but do not open the browser
    newToken*: bool ## serving, with a new secret token (the old bookmarks stop working)
    port*: int ## serving on this port (0: any free one)

  WebKind* = enum
    wkServe ## the default: show the page in the browser, served on localhost
    wkFile ## `--file`: make the file and print its path
    wkWorker ## for programs: also make the page, and print the paths

  WebMode* = object ## What the web options ask for.
    case kind*: WebKind
    of wkServe:
      noOpen*: bool
      newToken*: bool
      port*: int
    of wkFile, wkWorker:
      discard

func initWebArgs*(): WebArgs =
  ## The defaults: the default port, the rest off.
  WebArgs(port: defaultPort)

proc takePort*(name, value: string, port: var int): Problem =
  ## The value of `--port`: a port number.
  var n = 0
  if not parseIntIn(value, 0, 65535, n):
    return valueIs(name, "a port number, 0 to 65535", value)
  port = n
  fine

template webOptions*(P: typedesc, field: untyped, page, data: string): seq[Opt[P]] =
  ## The web options as options of a command whose `P` holds them in `field` (a `WebArgs`): `page` is what is shown
  ## ("the map"), `data` the file it is drawn from ("GeoJSON").  Without `--file` or `--worker` the command serves the page
  ## and opens it.
  @[
    custom(
      P,
      ["--file"],
      false,
      "",
      "make the " & data &
        " file in the cache directory and print its path, instead of showing " & page &
        " in the browser",
      body = (p.field.file = true; fine),
    ),
    custom(
      P,
      ["--worker"],
      false,
      "",
      "for programs: also make the web page, and print its path, then the path of the " &
        data & " file, and nothing else",
      body = (p.field.worker = true; fine),
    ),
    custom(
      P,
      ["--port"],
      true,
      "N",
      "the port to serve " & page & " on (default " & $defaultPort &
        ", the keypad digits of \"mchoo\"; 0: any free one)",
      body = takePort(name, value, p.field.port),
    ),
    custom(
      P,
      ["--no-open"],
      false,
      "",
      "print the address but do not open the browser",
      body = (p.field.noOpen = true; fine),
    ),
    custom(
      P,
      ["--new-token"],
      false,
      "",
      "make a new secret (old bookmarks stop working; the secret is kept in the cache directory, readable only by you)",
      body = (p.field.newToken = true; fine),
    ),
  ]

func webMode*(w: WebArgs): Parsed[WebMode] =
  ## What the options ask for, or what is wrong with the combination.
  if w.file and w.worker:
    return problemWith[WebMode]("--file and --worker cannot be used together")
  let serving = w.noOpen or w.newToken or w.port != defaultPort
  if (w.file or w.worker) and serving:
    return problemWith[WebMode](
      "--no-open, --new-token and --port are for serving the page: they cannot be used with --file or --worker"
    )
  if w.file:
    parsedOk(WebMode(kind: wkFile))
  elif w.worker:
    parsedOk(WebMode(kind: wkWorker))
  else:
    parsedOk(
      WebMode(kind: wkServe, noOpen: w.noOpen, newToken: w.newToken, port: w.port)
    )

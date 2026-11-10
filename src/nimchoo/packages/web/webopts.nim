## The options every command with web pages takes (`--worker`, `--web` and what goes with it):
## parsed and described in one place, so that the commands cannot differ.  Pure.

import ../util/args/args
import ./request

{.push raises: [].}

type
  WebArgs* = object
    ## The web options as they are read (a builder: `webMode` turns them into a `WebMode` or says what is wrong).
    worker*: bool ## for programs: make the files, print the page's path, then the data's
    enabled*: bool ## `--web`: serve the page on localhost and open it in the browser
    noOpen*: bool ## ... but do not open the browser
    newToken*: bool ## ... with a new secret token (the old bookmarks stop working)
    port*: int ## ... on this port (0: any free one)

  WebKind* = enum
    wkNone ## no web options: the command does its ordinary work
    wkWorker ## for programs: also make the page, and print the paths
    wkServe ## show the page in the browser, served on localhost

  WebMode* = object ## What the web options ask for.
    case kind*: WebKind
    of wkServe:
      noOpen*: bool
      newToken*: bool
      port*: int
    of wkNone, wkWorker:
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
  ## ("the map"), `data` the file it is drawn from ("GeoJSON").  The ones that go with `--web` are under it.
  @[
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
      ["--web"],
      false,
      "",
      "show " & page &
        " in the browser: make the files, serve them on localhost (this computer only) and open the address; Ctrl-C stops it",
      body = (p.field.enabled = true; fine),
    ),
    custom(
      P,
      ["--port"],
      true,
      "N",
      "the port for --web (default " & $defaultPort &
        ", the keypad digits of \"mchoo\"; 0: any free one)",
      level = 1,
      body = takePort(name, value, p.field.port),
    ),
    custom(
      P,
      ["--no-open"],
      false,
      "",
      "print the address but do not open the browser",
      level = 1,
      body = (p.field.noOpen = true; fine),
    ),
    custom(
      P,
      ["--new-token"],
      false,
      "",
      "make a new secret (old bookmarks stop working; the secret is kept in the cache directory, readable only by you)",
      level = 1,
      body = (p.field.newToken = true; fine),
    ),
  ]

func webMode*(w: WebArgs): Parsed[WebMode] =
  ## What the options ask for, or what is wrong with the combination.
  if w.enabled and w.worker:
    return problemWith[WebMode]("--web and --worker cannot be used together")
  if not w.enabled and (w.noOpen or w.newToken or w.port != defaultPort):
    return problemWith[WebMode]("--no-open, --new-token and --port go with --web")
  if w.enabled:
    parsedOk(
      WebMode(kind: wkServe, noOpen: w.noOpen, newToken: w.newToken, port: w.port)
    )
  elif w.worker:
    parsedOk(WebMode(kind: wkWorker))
  else:
    parsedOk(WebMode(kind: wkNone))

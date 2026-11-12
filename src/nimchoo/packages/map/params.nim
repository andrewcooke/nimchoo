## The command line of `nch map`, parsed.  Pure.  `--layers` says what is drawn; `--selection` and `--state` are for urls: the
## address a page has carries them (`selection=...&state=...`), and the server hands them to the worker.  The options are
## marked as allowed in an address, so the list of what a page may be given is made from here (`web/request.pageOf`).

import std/[options, strutils]
import ../selection/bits
import ../util/args/args
import ../web/[request, webopts]

{.push raises: [].}

type
  Layer* = enum
    ## What a map can show; each is a set of features of the file with its own `kind`, and the page decides the look.
    lyRoutes = "routes" ## the route of each activity
    lyClimbs = "climbs" ## the climbs they went up
    lyHeat = "heat"
      ## how often each place was visited, as cells of the grid (geo/cells.nim)
    lyGates = "gates"
      ## the two gates of each climb: the lines a ride has to cross to be on it
    lyEfforts = "efforts"
      ## the part of each ride that counts as an effort on a climb (between its stored start and finish)

  Target* = enum
    tSelection ## the current selection
    tList ## the activities of an address

  Params* = object
    web*: WebMode ## `--worker`, `--web` and what goes with it
    layers*: set[Layer] ## what to draw (never empty)
    case target*: Target
    of tSelection:
      discard
    of tList:
      selection*: string ## the activities to draw, as in an address (selection/bits.nim)
      state*: Option[string]
        ## a short hash of the content of those activities, which they must still have

  Raw = object ## what the options fill in
    help: bool
    selection, state, layers: string
    web: WebArgs

const defaultLayers* = {lyRoutes, lyClimbs} ## what a map shows when it is not told

func parseLayers*(text: string): Option[set[Layer]] =
  ## The layers a list names ("routes,heat"); none if it names one that is not there or none at all.
  var layers: set[Layer]
  for word in text.split(','):
    var found = false
    for l in Layer:
      if $l == word:
        layers.incl l
        found = true
    if not found:
      return none(set[Layer])
  some(layers)

func layersText*(layers: set[Layer]): string =
  ## The list of layers in its one spelling (in the order of the layers), as an address carries it.
  var names: seq[string]
  for l in Layer:
    if l in layers:
      names.add $l
  names.join(",")

func layerNames*(): seq[string] =
  ## The names of the layers, for completing the option.
  for l in Layer:
    result.add $l

func layersValue(value: string): bool =
  parseLayers(value).isSome

func bitsValue(value: string): bool =
  ## A list of activities: it may have two dashes in a row, and be long.
  value.len > 0 and isBitsString(value)

func mapSpec*(): Spec[Raw] =
  ## The options of `nch map`, with the web options.
  Spec[Raw](
    opts:
      @[
        custom(
          Raw,
          ["--layers"],
          true,
          "LIST",
          "what to draw, separated by commas: routes (the route of each activity), climbs (the climbs they went up), heat (how often each place was visited, in cells of about 100 m, coarser when zoomed out), gates (the start and finish line of each climb) and efforts (the part of each ride between the start and finish times of its efforts on climbs: for looking at how climbs are matched, with a few activities); default: routes,climbs",
          completion = Completion(kind: ckWords, words: layerNames()),
          address = adValue,
          valid = layersValue,
          body = (
            block:
              if not layersValue(value):
                return refuse(
                  "'" & value & "' is not a list of layers (" & layerNames().join(", ") &
                    ")"
                )
              p.layers = value
              fine
          ),
        ),
        custom(
          Raw,
          ["--selection"],
          true,
          "LIST",
          "for urls: the activities to draw, as in the address (default: the current selection)",
          address = adValue,
          valid = bitsValue,
          body = (
            block:
              if not bitsValue(value):
                return refuse("'" & value & "' is not a list of activities")
              p.selection = value
              fine
          ),
        ),
        custom(
          Raw,
          ["--state"],
          true,
          "HASH",
          "for urls, with --selection: a check that they are still the activities the address was made for",
          address = adValue,
          valid = hexHash,
          body = (
            block:
              if value.len > 64 or not hexHash(value):
                return refuse("'" & value & "' is not a state of activities")
              p.state = value
              fine
          ),
        ),
      ] & webOptions(Raw, web, "the map", "GeoJSON") & @[helpFlag(Raw)]
  )

func finish(raw: Raw): Parsed[Params] =
  let mode = webMode(raw.web)
  if mode.kind == pkProblem:
    return problemWith[Params](mode.problem)
  if raw.state.len > 0 and raw.selection.len == 0:
    return problemWith[Params]("--state goes with --selection")
  let layers =
    if raw.layers.len == 0:
      defaultLayers
    else:
      parseLayers(raw.layers).get # (`layersValue` has seen it)
  if raw.selection.len == 0:
    parsedOk(Params(target: tSelection, web: mode.params, layers: layers))
  else:
    parsedOk(
      Params(
        target: tList,
        web: mode.params,
        layers: layers,
        selection: raw.selection,
        state: (if raw.state.len > 0: some(raw.state) else: none(string)),
      )
    )

proc parseArgs*(args: seq[string]): Parsed[Params] =
  ## `--layers LIST`, `--selection STRING`, `--state HASH`, `--worker`, `--web` (with `--no-open`, `--port N`, `--new-token`), `-h`.
  parseCommand(args, mapSpec(), Raw(web: initWebArgs()), finish)

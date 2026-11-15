## The command line of `nch map`, parsed.  Pure.  `--layers` (words) says what is drawn (what is drawn of is the selection, as it
## is when the map is made).  The options are marked as allowed in an address (`/map?layers=routes,heat`), so the list of what a
## page may be given is made from here (`web/request.pageOf`).

import std/[options, strutils]
import ../util/args/args
import ../web/webopts

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

  Params* = object
    web*: WebMode ## `--file`, `--worker` and the options of serving
    layers*: set[Layer] ## what to draw (never empty)

  Raw = object ## what the options fill in
    help: bool
    layers: seq[string]
    web: WebArgs

const defaultLayers* = {lyRoutes, lyClimbs} ## what a map shows when it is not told

func layerOf(word: string): Option[Layer] =
  for l in Layer:
    if $l == word:
      return some(l)

func parseLayers*(words: seq[string]): Option[set[Layer]] =
  ## The layers a list names ("routes" "heat"); none if it names one that is not there or none at all.
  var layers: set[Layer]
  for word in words:
    let l = layerOf(word)
    if l.isNone:
      return none(set[Layer])
    layers.incl l.get
  if words.len == 0:
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

func layerValue(value: string): bool =
  layerOf(value).isSome

proc takeLayers(p: var Raw, name: string, values: seq[string]): Problem {.nimcall.} =
  if values.len == 0:
    return refuse(name & " needs at least one layer (" & layerNames().join(", ") & ")")
  for v in values:
    if not layerValue(v):
      return refuse("'" & v & "' is not a layer (" & layerNames().join(", ") & ")")
  p.layers.add values
  fine

func mapSpec*(): Spec[Raw] =
  ## The options of `nch map`, with the web options.
  Spec[Raw](
    opts:
      @[
        listOption[Raw](
          ["--layers"],
          takeLayers,
          "LAYER...",
          "what to draw, separated by spaces: routes (the route of each activity), climbs (the climbs they went up), heat (how often each place was visited, in cells of about 100 m, coarser when zoomed out), gates (the start and finish line of each climb) and efforts (the part of each ride between the start and finish times of its efforts on climbs: for looking at how climbs are matched, with a few activities); default: routes climbs",
          completion = Completion(kind: ckWords, words: layerNames()),
          address = adList,
          valid = layerValue,
        )
      ] & webOptions(Raw, web, "the map", "GeoJSON") & @[helpFlag(Raw)]
  )

func finish(raw: Raw): Parsed[Params] =
  let mode = webMode(raw.web)
  if mode.kind == pkProblem:
    return problemWith[Params](mode.problem)
  let layers =
    if raw.layers.len == 0:
      defaultLayers
    else:
      parseLayers(raw.layers).get # (`takeLayers` has seen them)
  parsedOk(Params(web: mode.params, layers: layers))

proc parseArgs*(args: seq[string]): Parsed[Params] =
  ## `--layers LAYER...`, `--file`, `--worker`, `--port N`, `--no-open`, `--new-token`, `-h`.
  parseCommand(args, mapSpec(), Raw(web: initWebArgs()), finish)

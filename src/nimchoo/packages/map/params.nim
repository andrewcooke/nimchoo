## The command line of `nch map`, parsed.  Pure.  There are only the two options that say what is drawn, and they are
## for programs: the address a page has carries them (`bits=...&check=...`), and the server hands them to the worker.  Those
## options are marked as allowed in an address, so the list of what a page may be given is made from here
## (`web/request.pageOf`).

import std/options
import ../selection/bits
import ../util/args/args
import ../web/[request, webopts]

{.push raises: [].}

type
  Target* = enum
    tSelection ## the current selection
    tList ## the activities of an address

  Params* = object
    web*: WebMode ## `--worker`, `--web` and what goes with it
    case target*: Target
    of tSelection:
      discard
    of tList:
      bits*: string ## the activities to draw, as in an address (selection/bits.nim)
      check*: Option[string]
        ## a short hash of the content of those activities, which they must still have

  Raw = object ## what the options fill in
    help: bool
    bits, check: string
    web: WebArgs

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
          ["--bits"],
          true,
          "LIST",
          "for programs: the activities to draw, as in the address (default: the current selection)",
          address = adValue,
          valid = bitsValue,
          body = (
            block:
              if not bitsValue(value):
                return refuse("'" & value & "' is not a list of activities")
              p.bits = value
              fine
          ),
        ),
        custom(
          Raw,
          ["--check"],
          true,
          "HASH",
          "for programs, with --bits: a check that they are still the activities the address was made for",
          address = adValue,
          valid = hexHash,
          body = (
            block:
              if value.len > 64 or not hexHash(value):
                return refuse("'" & value & "' is not a check of activities")
              p.check = value
              fine
          ),
        ),
      ] & webOptions(Raw, web, "the map", "GeoJSON") & @[helpFlag(Raw)]
  )

func finish(raw: Raw): Parsed[Params] =
  let mode = webMode(raw.web)
  if mode.kind == pkProblem:
    return problemWith[Params](mode.problem)
  if raw.check.len > 0 and raw.bits.len == 0:
    return problemWith[Params]("--check goes with --bits")
  if raw.bits.len == 0:
    parsedOk(Params(target: tSelection, web: mode.params))
  else:
    parsedOk(
      Params(
        target: tList,
        web: mode.params,
        bits: raw.bits,
        check: (if raw.check.len > 0: some(raw.check) else: none(string)),
      )
    )

proc parseArgs*(args: seq[string]): Parsed[Params] =
  ## `--bits STRING`, `--check HASH`, `--worker`, `--web` (with `--no-open`, `--port N`, `--new-token`), `-h`.
  parseCommand(args, mapSpec(), Raw(web: initWebArgs()), finish)

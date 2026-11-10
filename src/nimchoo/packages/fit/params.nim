## The command line of `nch fit`, parsed.  Pure.

import std/options
import ../util/args/args

{.push raises: [].}

type
  Params* = object
    file*: string ## the FIT file to read
    csv*: bool ## SDK-format CSV, not text
    profile*: Option[string] ## the profile to use instead of the built-in one

  Raw = object ## what the options fill in
    help, csv: bool
    profile: string
    files: seq[string]

func fitSpec*(): Spec[Raw] =
  ## The options of `nch fit`; the file is the positional argument.
  Spec[Raw](
    opts: @[
      flag(
        Raw, ["--csv"], csv, "SDK-format CSV (including definitions) instead of text"
      ),
      text(
        Raw,
        ["--profile"],
        profile,
        "PATH",
        "use this Profile.xlsx instead of the built-in one",
        completion = Completion(kind: ckFile),
      ),
      helpFlag(Raw),
    ],
    positional: proc(p: var Raw, arg: string): Problem {.nimcall, raises: [].} =
      p.files.add arg
      fine,
  )

func finish(raw: Raw): Parsed[Params] =
  if raw.files.len != 1:
    return problemWith[Params]("expected exactly one FILE")
  parsedOk(
    Params(
      file: raw.files[0],
      csv: raw.csv,
      profile: (if raw.profile.len > 0: some(raw.profile)
      else: none(string)),
    )
  )

proc parseArgs*(args: seq[string]): Parsed[Params] =
  ## `nch fit [--csv] [--profile PATH] FILE`.
  parseCommand(args, fitSpec(), Raw(), finish)

## What an option is, for people (the usage) and for the shell (tab completion).  It is in `core` so that a command's
## declaration (`CommandDecl.options`) can carry the descriptions of its options and `nch __complete` can read them from the
## registry; the parser that makes them (`util/args`) re-exports these types.

import ./[errors, globals]

{.push raises: [].}

type
  Provider* =
    proc(g: Globals, typed: string): seq[string] {.nimcall, raises: [StoreError].}
    ## The values an option may have, from the program's data: the ones that start with what is typed (whatever the case and
    ## accents, if the option is; each provider says).  It opens the database as `g` says (`openStore(g)`), which is
    ## read-only when completing; if it raises `StoreError` (no database, another version) nothing is offered.

  CompletionKind* = enum
    ckNone ## nothing is offered
    ckFile ## a file or a directory
    ckWords ## one of `Completion.words`
    ckDynamic ## whatever `Completion.provide` says, from the program's data

  Completion* = object ## what a shell may offer for the value of an option
    case kind*: CompletionKind
    of ckNone, ckFile:
      discard
    of ckWords:
      words*: seq[string]
    of ckDynamic:
      provide*: Provider

  Arity* = enum
    aFlag ## no value
    aOne ## one value
    aOptional
      ## one value that may be left out: the next word is it unless that is an option
    aList ## any number of values (words up to the next option)

  OptDoc* = object
    ## what an option is, for people (the usage) and for the shell (completion)
    names*: seq[string] ## "-n", "--newest"
    metavar*: string
      ## the value, as the usage shows it: "N", "TEXT...", "LAT,LON" ("" for a flag)
    help*: string ## prose, wrapped by the usage; a "\n" starts a new paragraph of it
    arity*: Arity
    completion*: Completion
    level*: int
      ## 0, or 1 for an option that goes with the one before it (`--rename` under `--edit`): indented

func completesFrom*(provide: Provider): Completion =
  ## A completion from the program's data.
  doAssert not provide.isNil, "a dynamic completion needs its provider"
  Completion(kind: ckDynamic, provide: provide)

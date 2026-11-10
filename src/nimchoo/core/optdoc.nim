## What an option is, for people (the usage) and for the shell (tab completion).  It is in `core` so that a command's
## declaration (`CommandDecl.options`) can carry the descriptions of its options and `nch __complete` can read them from the
## registry; the parser that makes them (`util/args`) re-exports these types.

{.push raises: [].}

type
  CompletionKind* = enum
    ckNone ## nothing is offered
    ckFile ## a file or a directory
    ckWords ## one of `Completion.words`
    ckDynamic
      ## from the program's data, by the name in `Completion.source` ("sport", "climb")

  Completion* = object ## what a shell may offer for the value of an option
    kind*: CompletionKind
    words*: seq[string]
    source*: string

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

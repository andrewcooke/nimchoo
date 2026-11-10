## One command-line parser for all the commands.  A command describes its options as a list
## (`Opt`s: the names, whether there is a value, what to do with it) and `parseOptions` does the
## walking: the value that is missing, the option that is unknown, the arguments that are not
## options.  What a value means stays with the command, in the small procs it hands over.
##
## An option also describes itself (`OptDoc`: names, the placeholder for its value, its help, what could complete it),
## and the usage text is made from the descriptions (`usage.nim`), so the option list is written once.  A package that
## offers an option to another's command (an activity criterion) hands over just the description.
##
## An option's `apply` returns `fine` if all is well, else `refuse(what is wrong)` (a sentence that does not
## name the option: the parser adds `--name is ...` where it can, see `valueIs`).  A command's `parseArgs` gives a
## `Parsed[T]`: help asked for, a problem, or parameters that are valid (a variant on the action, built by the command's
## own `finish`).  An option may be allowed in an address (`address`, with a check for its value): the server's list of
## what a page may be given is made from the same options, so it cannot differ from what the command parses.  Pure.

import std/[math, options, strutils]

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
    aList ## any number of values (words up to the next option)

  Problem* = Option[string]
    ## what is wrong with an option or a command line; none if nothing

  Validator* = proc(value: string): bool {.noSideEffect, nimcall, raises: [].}
    ## What a value may be: true if this one may.

  Address* = enum
    adNo ## not given in the address of a page
    adFlag ## `?name=1` becomes `--name`
    adValue
      ## `?name=value` becomes `--name value`, if the option's `valid` accepts the value

  ParseKind* = enum
    pkOk
    pkHelp
    pkProblem

  Parsed*[T] = object
    ## What a command line came to: a valid command (`params`), a request for help, or a problem to say.
    case kind*: ParseKind
    of pkOk:
      params*: T
    of pkHelp:
      discard
    of pkProblem:
      why*: string ## what is wrong, as a sentence

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

  Apply*[P] = proc(p: var P, name, value: string): Problem {.nimcall, raises: [].}
    ## Take an option (`name` is the way it was spelt); `value` is "" for a flag.

  ApplyList*[P] =
    proc(p: var P, name: string, values: seq[string]): Problem {.nimcall, raises: [].}
    ## Take an option that has any number of values (`--sport cycling running`): the words up
    ## to the next option.

  Opt*[P] = object
    names*: seq[string] ## "-h", "--help"
    takesValue*: bool
    apply*: Apply[P]
    takesList*: bool ## then `applyList` is used, not `apply`
    applyList*: ApplyList[P]
    metavar*: string
    help*: string
    completion*: Completion
    level*: int
    address*: Address
    valid*: Validator ## for `adValue`: what the value may be

  Positional*[P] = proc(p: var P, arg: string): Problem {.nimcall, raises: [].}

  Spec*[P] = object
    opts*: seq[Opt[P]]
    positional*: Positional[P] ## nil: only options are allowed
    hint*: proc(arg: string): string {.nimcall, raises: [].}
      ## nil, or extra words for "unexpected argument X" (like " (to add a model: --add X)")

const fine* = none(string) ## nothing is wrong

func refuse*(why: string): Problem =
  ## Something is wrong: say what, in a sentence that does not name the option.
  some(why)

func problemWith*[T](why: string): Parsed[T] =
  Parsed[T](kind: pkProblem, why: why)

func problem*[T](p: Parsed[T]): string =
  ## What is wrong with the command line, "" if nothing is (for a message, or a test).
  if p.kind == pkProblem: p.why else: ""

func help*[T](p: Parsed[T]): bool =
  ## Whether help was asked for.
  p.kind == pkHelp

func helpAsked*[T](): Parsed[T] =
  Parsed[T](kind: pkHelp)

func parsedOk*[T](params: T): Parsed[T] =
  Parsed[T](kind: pkOk, params: params)

func find[P](spec: Spec[P], name: string): int =
  for k, o in spec.opts:
    if name in o.names:
      return k
  -1

proc walk[P](
    args: seq[string], spec: Spec[P], p: var P, leading: bool, next: var int
): Problem =
  var i = 0
  while i < args.len:
    let a = args[i]
    if leading and not (a.len > 1 and a.startsWith("-")):
      next = i
      return
    # `--name=value` is the same as `--name value`
    let eq =
      if a.startsWith("--"):
        a.find('=')
      else:
        -1
    let name =
      if eq > 0:
        a[0 ..< eq]
      else:
        a
    let k =
      if a.len > 1 and a.startsWith("-"):
        spec.find(name)
      else:
        -1
    if k >= 0:
      let o = spec.opts[k]
      var v = ""
      if o.takesList:
        var values: seq[string]
        if eq > 0:
          values.add a[eq + 1 .. ^1]
        else:
          while i + 1 < args.len and not args[i + 1].startsWith("-"):
            inc i
            values.add args[i]
        let why = o.applyList(p, name, values)
        if why.isSome:
          return why
        inc i
        continue
      if o.takesValue:
        if eq > 0:
          v = a[eq + 1 .. ^1]
        else:
          inc i
          if i >= args.len:
            return refuse(name & " needs a value")
          v = args[i]
      elif eq > 0:
        return refuse(name & " does not take a value")
      let why = o.apply(p, name, v)
      if why.isSome:
        return why
    elif a.len > 1 and a.startsWith("-"):
      # the options every command has are given before its name: say so, as that is the likely mistake
      if name == "--user":
        return refuse(
          "unexpected option " & a &
            " (it goes before the command: nch --user NAME COMMAND ...)"
        )
      if name == "--db":
        return refuse(
          "unexpected option " & a &
            " (it goes before the command: nch --db PATH COMMAND ...)"
        )
      return refuse("unexpected option " & a)
    elif spec.positional != nil:
      let why = spec.positional(p, a)
      if why.isSome:
        return why
    else:
      return refuse(
        "unexpected argument " & a & (if spec.hint != nil: spec.hint(a)
        else: "")
      )
    inc i

proc parseOptions*[P](args: seq[string], spec: Spec[P], p: var P): Problem =
  ## Walk the arguments.  Returns the first problem found.
  var next = 0
  walk(args, spec, p, false, next)

proc parseLeading*[P](
    args: seq[string], spec: Spec[P], p: var P, next: var int
): Problem =
  ## Take the options at the start of the arguments, up to the first argument that is not one
  ## (the command, for the options every command has); `next` is where that is, `args.len` if
  ## there is none.  Returns the first problem found.
  next = args.len
  walk(args, spec, p, true, next)

func doc*[P](o: Opt[P]): OptDoc =
  ## The description of the option.
  OptDoc(
    names: o.names,
    metavar: o.metavar,
    help: o.help,
    arity:
      if o.takesList:
        aList
      elif o.takesValue:
        aOne
      else:
        aFlag,
    completion: o.completion,
    level: o.level,
  )

func docs*[P](spec: Spec[P]): seq[OptDoc] =
  ## The descriptions of the options, in order.
  for o in spec.opts:
    result.add o.doc

func listOption*[P](
    nameList: openArray[string],
    apply: ApplyList[P],
    metavar, help: string,
    level = 0,
    completion = Completion(),
): Opt[P] =
  ## An option with any number of values, described.
  Opt[P](
    names: @nameList,
    takesList: true,
    applyList: apply,
    metavar: metavar,
    help: help,
    level: level,
    completion: completion,
  )

func valueIs*(name, what, value: string): Problem =
  ## "--fthr is a whole number of beats per minute, 80 to 230 (not 'x')"
  refuse(name & " is " & what & " (not '" & value & "')")

func parseFloatIn*(v: string, lo, hi: float, x: var float): bool =
  ## A number from `lo` up to `hi` (both included), not NaN or infinite.
  try:
    x = parseFloat(v)
  except ValueError:
    return false
  x == x and x >= lo and x <= hi and classify(x) notin {fcInf, fcNegInf}

func parseIntIn*(v: string, lo, hi: int, n: var int): bool =
  ## Read a whole number from `v` into `n` if it is between `lo` and `hi`; whether it was.
  try:
    n = parseInt(v)
  except ValueError:
    return false
  n >= lo and n <= hi

func described*[P](
    o: Opt[P],
    metavar, help: string,
    level: int = 0,
    completion: Completion = Completion(),
    address: Address = adNo,
    valid: Validator = nil,
): Opt[P] =
  ## The option with its description: how the usage shows its value (`metavar`), what it does (`help`), whether it is
  ## indented under the one before (`level`), what completes it, and whether and how it may be given in an address.
  ## (The templates below make options through this, because a template parameter called `help` would replace the
  ## field of that name.)
  result = o
  result.metavar = metavar
  result.help = help
  result.level = level
  result.completion = completion
  result.address = address
  result.valid = valid

# Building options.  The field is named in the template and so is a plain field access: the proc
# made is an ordinary one (no closure), as `Apply` needs.  Each kind comes twice: with the option's description (the
# way to write an option) and without (`documented` adds it afterwards: for the commands not yet converted).

template flag*(
    P: typedesc,
    nameList: openArray[string],
    field: untyped,
    help: string,
    level: int = 0,
    address: Address = adNo,
): Opt[P] =
  ## A described option without a value, which sets a bool field.
  described(
    Opt[P](
      names: @nameList,
      takesValue: false,
      apply: proc(p: var P, name, value: string): Problem {.nimcall, raises: [].} =
        p.field = true
        fine,
    ),
    "",
    help,
    level,
    Completion(),
    address,
    nil,
  )

template text*(
    P: typedesc,
    nameList: openArray[string],
    field: untyped,
    metavar, help: string,
    level: int = 0,
    completion: Completion = Completion(),
    address: Address = adNo,
    valid: Validator = nil,
): Opt[P] =
  ## A described option with a value that is kept as it is.
  described(
    Opt[P](
      names: @nameList,
      takesValue: true,
      apply: proc(p: var P, name, value: string): Problem {.nimcall, raises: [].} =
        p.field = value
        fine,
    ),
    metavar,
    help,
    level,
    completion,
    address,
    valid,
  )

template number*(
    P: typedesc,
    nameList: openArray[string],
    field: untyped,
    lo, hi: float,
    what, metavar, help: string,
    level: int = 0,
    address: Address = adNo,
    valid: Validator = nil,
): Opt[P] =
  ## A described option whose value is a number from `lo` to `hi`.
  described(
    Opt[P](
      names: @nameList,
      takesValue: true,
      apply: proc(p: var P, name, value: string): Problem {.nimcall, raises: [].} =
        var x = 0.0
        if not parseFloatIn(value, lo, hi, x):
          return valueIs(name, what, value)
        p.field = x
        fine,
    ),
    metavar,
    help,
    level,
    Completion(),
    address,
    valid,
  )

template whole*(
    P: typedesc,
    nameList: openArray[string],
    field: untyped,
    lo, hi: int,
    what, metavar, help: string,
    level: int = 0,
    address: Address = adNo,
    valid: Validator = nil,
): Opt[P] =
  ## A described option whose value is a whole number from `lo` to `hi`.
  described(
    Opt[P](
      names: @nameList,
      takesValue: true,
      apply: proc(p: var P, name, value: string): Problem {.nimcall, raises: [].} =
        var n = 0
        if not parseIntIn(value, lo, hi, n):
          return valueIs(name, what, value)
        p.field = n
        fine,
    ),
    metavar,
    help,
    level,
    Completion(),
    address,
    valid,
  )

template custom*(
    P: typedesc,
    nameList: openArray[string],
    takes: bool,
    metavar, help: string,
    level: int = 0,
    completion: Completion = Completion(),
    address: Address = adNo,
    valid: Validator = nil,
    body: untyped,
): Opt[P] =
  ## A described option with its own handling: `body` sees `p`, `name` and `value` and gives the `Problem`
  ## (`fine`, or `refuse("...")`) as its last expression.
  described(
    Opt[P](
      names: @nameList,
      takesValue: takes,
      apply: proc(
          p {.inject.}: var P, name {.inject.}, value {.inject.}: string
      ): Problem {.nimcall, raises: [].} =
        body,
    ),
    metavar,
    help,
    level,
    completion,
    address,
    valid,
  )

template helpFlag*(B: typedesc): Opt[B] =
  ## `-h, --help`, for a builder `B` that has a `help` field.
  flag(B, ["-h", "--help"], help, "show this help")

proc parseCommand*[B, T](
    args: seq[string],
    spec: Spec[B],
    start: B,
    finish: proc(raw: B): Parsed[T] {.nimcall, raises: [].},
): Parsed[T] =
  ## Read the arguments into a builder `B` (which has a `help` field, set by `helpFlag`), then `finish` it: the
  ## command's own step that turns what was read into valid parameters, or says what is wrong with the combination.
  var raw = start
  let why = parseOptions(args, spec, raw)
  if why.isSome:
    return problemWith[T](why.get)
  if raw.help:
    return helpAsked[T]()
  finish(raw)

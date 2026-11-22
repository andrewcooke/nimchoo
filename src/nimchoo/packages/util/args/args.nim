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
## `Parsed[T]`: help asked for, a problem, a number given without its unit (`pkUnit`: the options that have a default unit,
## `withUnit`, read a bare number as if it had that unit and say so; `core/unitfix.nim` has what a command does about it), or parameters that are valid (a variant on the action, built by the command's
## own `finish`).  An option may be allowed in an address (`address`, with a check for its value): the server's list of
## what a page may be given is made from the same options, so it cannot differ from what the command parses.  Pure.

import std/[math, options, strutils]
import ../../../core/[line, optdoc, unitfix]
import ../../ui/[markup, units]
export optdoc, line, markup, unitfix

{.push raises: [].}

type
  Problem* = Option[Line]
    ## what is wrong with an option or a command line; none if nothing

  Validator* = proc(value: string): bool {.noSideEffect, nimcall, raises: [].}
    ## What a value may be: true if this one may.

  AddUnit* =
    proc(value, unit: string): Option[string] {.nimcall, noSideEffect, raises: [].}
    ## The value with the default `unit` added where it is missing; none if it needs none.

  Address* = enum
    adNo ## not given in the address of a page
    adFlag ## `?name=1` becomes `--name`
    adValue
      ## `?name=value` becomes `--name value`, if the option's `valid` accepts the value (a list option is never in an
      ## address)

  ParseKind* = enum
    pkOk
    pkHelp
    pkProblem
    pkUnit

  Parsed*[T] = object
    ## What a command line came to: a valid command (`params`), a request for help, or a problem to say.
    case kind*: ParseKind
    of pkOk:
      params*: T
    of pkHelp:
      discard
    of pkProblem:
      why*: Line ## what is wrong, as a sentence (`~"..."`)
    of pkUnit:
      fix*: UnitFix
        ## valid once the default unit is added to the numbers that had none: what they were, and the corrected arguments
        ## (`core/unitfix.unitRetry` asks, and runs the command again with them)

  Apply*[P] = proc(p: var P, name, value: string): Problem {.nimcall, raises: [].}
    ## Take an option (`name` is the way it was spelt); `value` is "" for a flag.

  ApplyList*[P] =
    proc(p: var P, name: string, values: seq[string]): Problem {.nimcall, raises: [].}
    ## Take an option that has any number of values (`--sport cycling running`): the words up
    ## to the next option.

  Opt*[P] = object
    names*: seq[string] ## "-h", "--help"
    arity*: Arity
      ## no value, one, one that may be left out (the next word is it unless that is an option: `apply` is then given "", as
      ## `nch --install-completion [SHELL]`), or a list (`applyList` is used, not `apply`): the one fact, which `doc` hands on
    apply*: Apply[P]
    applyList*: ApplyList[P]
    metavar*: string
    help*: Line
    completion*: Completion
    level*: int
    address*: Address
    unit*: string
      ## the unit a bare number is taken to have (`km`): "" if the option does not want a unit.  The command line is then
      ## a `pkUnit` (`UnitFix`), not an error: a person is asked whether that was meant
    addUnit*: AddUnit
      ## nil: a bare number is the text with the unit after it.  Else how to add `unit` to a value that has none, when that is
      ## not just the end of the value (a range, `40-`: `40km-`); none: the value has a unit, or none can be added
    valid*: Validator ## for `adValue`: what the value may be

  Positional*[P] = proc(p: var P, arg: string): Problem {.nimcall, raises: [].}

  Spec*[P] = object
    opts*: seq[Opt[P]]
    positional*: Positional[P] ## nil: only options are allowed
    hint*: proc(arg: string): Line {.nimcall, raises: [].}
      ## nil, or extra words for "unexpected argument X" (like " (to add a model: --add X)")

const fine* = none(Line) ## nothing is wrong

func refuse*(why: Line): Problem =
  ## Something is wrong: say what, in a sentence that does not name the option.
  some(why)

func withUnit*[P](o: Opt[P], unit: string, addUnit: AddUnit = nil): Opt[P] =
  ## The option reads a bare number as a number of `unit` (and the parse comes out as `pkUnit`, so that the person is asked).
  ## For a value that is more than a number (a range), `addUnit` says how the unit is added.
  result = o
  result.unit = unit
  result.addUnit = addUnit

func plainAddUnit(value, unit: string): Option[string] =
  var x: float
  var rest: string
  if unitNumber(value, x, rest) and rest.len == 0:
    some(value & unit)
  else:
    none(string)

func problemWith*[T](why: Line): Parsed[T] =
  Parsed[T](kind: pkProblem, why: why)

func problem*[T](p: Parsed[T]): string =
  ## What is wrong with the command line as text, "" if nothing is (for a test; a message says `why`).
  if p.kind == pkProblem: p.why.plainText else: ""

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

type Bare = object ## where a number without its unit was given
  at: int ## the index in the arguments of the value (or of `--name=value`)
  inName: bool ## it was `--name=value`
  fixed: string ## the value with the unit added
  item: Unitless

proc walk[P](
    args: seq[string],
    spec: Spec[P],
    p: var P,
    leading: bool,
    next: var int,
    bare: var seq[Bare],
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
      if o.arity == aList:
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
      if o.arity in {aOne, aOptional}:
        if eq > 0:
          v = a[eq + 1 .. ^1]
        elif o.arity == aOptional:
          if i + 1 < args.len and not args[i + 1].startsWith("-"):
            inc i
            v = args[i]
        else:
          inc i
          if i >= args.len:
            return refuse(~"`{name}` needs a value")
          v = args[i]
      elif eq > 0:
        return refuse(~"`{name}` does not take a value")
      if o.unit.len > 0 and o.arity in {aOne, aOptional} and v.len > 0:
        let fixed =
          if o.addUnit != nil:
            o.addUnit(v, o.unit)
          else:
            plainAddUnit(v, o.unit)
        if fixed.isSome:
          bare.add Bare(
            at: i,
            inName: eq > 0,
            fixed: fixed.get,
            item: Unitless(option: name, value: v, unit: o.unit),
          )
          v = fixed.get # (read as if it had been typed)
      let why = o.apply(p, name, v)
      if why.isSome:
        return why
    elif a.len > 1 and a.startsWith("-"):
      # the options every command has are given before its name: say so, as that is the likely mistake
      if name == "--user":
        return refuse(
          ~"unexpected option `{a}` (it goes before the command: `nch --user NAME COMMAND ...`)"
        )
      if name == "--db":
        return refuse(
          ~"unexpected option `{a}` (it goes before the command: `nch --db PATH COMMAND ...`)"
        )
      return refuse(~"unexpected option `{a}`")
    elif spec.positional != nil:
      let why = spec.positional(p, a)
      if why.isSome:
        return why
    else:
      return refuse(
        ~"unexpected argument {a}" & (if spec.hint != nil: spec.hint(a)
        else: @[])
      )
    inc i

func corrected(args: seq[string], bare: seq[Bare]): UnitFix =
  ## The arguments with the default unit added to each bare number.
  result.original = args
  result.args = args
  for b in bare:
    result.missing.add b.item
    let fixed = b.fixed
    result.args[b.at] =
      if b.inName:
        b.item.option & "=" & fixed
      else:
        fixed

proc parseOptionsFixing*[P](
    args: seq[string], spec: Spec[P], p: var P, fix: var UnitFix
): Problem =
  ## Walk the arguments.  Returns the first problem found.  A bare number given to an option that has a default unit
  ## (`withUnit`) is read with the unit added, and `fix` says what was changed (`fix.missing` is empty if nothing was).
  var next = 0
  var bare: seq[Bare]
  result = walk(args, spec, p, false, next, bare)
  fix = corrected(args, bare)

proc parseOptions*[P](args: seq[string], spec: Spec[P], p: var P): Problem =
  ## Walk the arguments.  Returns the first problem found.  (For a spec with no option that wants a unit.)
  var fix: UnitFix
  parseOptionsFixing(args, spec, p, fix)

proc parseLeading*[P](
    args: seq[string], spec: Spec[P], p: var P, next: var int
): Problem =
  ## Take the options at the start of the arguments, up to the first argument that is not one
  ## (the command, for the options every command has); `next` is where that is, `args.len` if
  ## there is none.  Returns the first problem found.
  next = args.len
  var bare: seq[Bare]
  walk(args, spec, p, true, next, bare)

func doc*[P](o: Opt[P]): OptDoc =
  ## The description of the option.
  OptDoc(
    names: o.names,
    metavar: o.metavar,
    help: o.help,
    arity: o.arity,
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
    metavar: string,
    help: Line,
    level = 0,
    completion = Completion(),
    valid: Validator = nil,
): Opt[P] =
  ## An option with any number of values, described.  Its name is plural and its values are separated by spaces.
  Opt[P](
    names: @nameList,
    arity: aList,
    applyList: apply,
    metavar: metavar,
    help: help,
    level: level,
    completion: completion,
    valid: valid,
  )

func valueIs*(name, what, value: string): Problem =
  ## "--fthr is a whole number of beats per minute, 80 to 230 (not 'x')"
  refuse(~"`{name}` is {what} (not '{value}')")

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
    metavar: string,
    help: Line,
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
    help: Line,
    level: int = 0,
    address: Address = adNo,
): Opt[P] =
  ## A described option without a value, which sets a bool field.
  described(
    Opt[P](
      names: @nameList,
      arity: aFlag,
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
    metavar: string,
    help: Line,
    level: int = 0,
    completion: Completion = Completion(),
    address: Address = adNo,
    valid: Validator = nil,
): Opt[P] =
  ## A described option with a value that is kept as it is.
  described(
    Opt[P](
      names: @nameList,
      arity: aOne,
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
    what, metavar: string,
    help: Line,
    level: int = 0,
    address: Address = adNo,
    valid: Validator = nil,
): Opt[P] =
  ## A described option whose value is a number from `lo` to `hi`.
  described(
    Opt[P](
      names: @nameList,
      arity: aOne,
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
    what, metavar: string,
    help: Line,
    level: int = 0,
    address: Address = adNo,
    valid: Validator = nil,
): Opt[P] =
  ## A described option whose value is a whole number from `lo` to `hi`.
  described(
    Opt[P](
      names: @nameList,
      arity: aOne,
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
    metavar: string,
    help: Line,
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
      arity: (if takes: aOne else: aFlag),
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

template optionalValue*(
    P: typedesc,
    nameList: openArray[string],
    metavar: string,
    help: Line,
    level: int = 0,
    completion: Completion = Completion(),
    body: untyped,
): Opt[P] =
  ## A described option whose value may be left out (`nch --install-completion [SHELL]`): `body` sees `p`, `name` and `value`
  ## ("" if it was left out) and gives the `Problem`, as for `custom`.
  described(
    Opt[P](
      names: @nameList,
      arity: aOptional,
      apply: proc(
          p {.inject.}: var P, name {.inject.}, value {.inject.}: string
      ): Problem {.nimcall, raises: [].} =
        body,
    ),
    metavar,
    help,
    level,
    completion,
    adNo,
    nil,
  )

template helpFlag*(B: typedesc): Opt[B] =
  ## `-h, --help`, for a builder `B` that has a `help` field.
  flag(B, ["-h", "--help"], help, ~"show this help")

proc parseCommand*[B, T](
    args: seq[string],
    spec: Spec[B],
    start: B,
    finish: proc(raw: B): Parsed[T] {.nimcall, raises: [].},
): Parsed[T] =
  ## Read the arguments into a builder `B` (which has a `help` field, set by `helpFlag`), then `finish` it: the
  ## command's own step that turns what was read into valid parameters, or says what is wrong with the combination.
  var raw = start
  var fix: UnitFix
  let why = parseOptionsFixing(args, spec, raw, fix)
  if why.isSome:
    return problemWith[T](why.get)
  if raw.help:
    return helpAsked[T]()
  result = finish(raw)
  if result.kind == pkOk and fix.missing.len > 0:
    result = Parsed[T](kind: pkUnit, fix: fix)

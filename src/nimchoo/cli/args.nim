## One command-line parser for all the commands.  A command describes its options as a list
## (`Opt`s: the names, whether there is a value, what to do with it) and `parseOptions` does the
## walking: the value that is missing, the option that is unknown, the arguments that are not
## options.  What a value means stays with the command, in the small procs it hands over.
##
## An option's `apply` returns "" if all is well, else what is wrong (a sentence that does not
## name the option: the parser adds `--name is ...` where it can, see `valueIs`).  Pure.

import std/[math, strutils]

{.push raises: [].}

type
  Apply*[P] = proc(p: var P, name, value: string): string {.nimcall, raises: [].}
    ## Take an option (`name` is the way it was spelt); `value` is "" for a flag.

  ApplyList*[P] =
    proc(p: var P, name: string, values: seq[string]): string {.nimcall, raises: [].}
    ## Take an option that has any number of values (`--sport cycling running`): the words up
    ## to the next option.

  Opt*[P] = object
    names*: seq[string] ## "-h", "--help"
    takesValue*: bool
    apply*: Apply[P]
    takesList*: bool ## then `applyList` is used, not `apply`
    applyList*: ApplyList[P]

  Positional*[P] = proc(p: var P, arg: string): string {.nimcall, raises: [].}

  Spec*[P] = object
    opts*: seq[Opt[P]]
    positional*: Positional[P] ## nil: only options are allowed
    hint*: proc(arg: string): string {.nimcall, raises: [].}
      ## nil, or extra words for "unexpected argument X" (like " (to add a model: --add X)")

func find[P](spec: Spec[P], name: string): int =
  for k, o in spec.opts:
    if name in o.names:
      return k
  -1

proc walk[P](
    args: seq[string], spec: Spec[P], p: var P, leading: bool, next: var int
): string =
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
        if why.len > 0:
          return why
        inc i
        continue
      if o.takesValue:
        if eq > 0:
          v = a[eq + 1 .. ^1]
        else:
          inc i
          if i >= args.len:
            return name & " needs a value"
          v = args[i]
      elif eq > 0:
        return name & " does not take a value"
      let why = o.apply(p, name, v)
      if why.len > 0:
        return why
    elif a.len > 1 and a.startsWith("-"):
      # the options every command has are given before its name: say so, as that is the likely mistake
      if name == "--user":
        return
          "unexpected option " & a &
          " (it goes before the command: nch --user NAME COMMAND ...)"
      if name == "--db":
        return
          "unexpected option " & a &
          " (it goes before the command: nch --db PATH COMMAND ...)"
      return "unexpected option " & a
    elif spec.positional != nil:
      let why = spec.positional(p, a)
      if why.len > 0:
        return why
    else:
      return "unexpected argument " & a & (if spec.hint != nil: spec.hint(a)
      else: "")
    inc i

proc parseOptions*[P](args: seq[string], spec: Spec[P], p: var P): string =
  ## Walk the arguments.  Returns the first problem found, "" if there is none.
  var next = 0
  walk(args, spec, p, false, next)

proc parseLeading*[P](
    args: seq[string], spec: Spec[P], p: var P, next: var int
): string =
  ## Take the options at the start of the arguments, up to the first argument that is not one
  ## (the command, for the options every command has); `next` is where that is, `args.len` if
  ## there is none.  Returns the first problem found, "" if there is none.
  next = args.len
  walk(args, spec, p, true, next)

func listOption*[P](nameList: openArray[string], apply: ApplyList[P]): Opt[P] =
  ## An option with any number of values.
  Opt[P](names: @nameList, takesList: true, applyList: apply)

func valueIs*(name, what, value: string): string =
  ## "--fthr is a whole number of beats per minute, 80 to 230 (not 'x')"
  name & " is " & what & " (not '" & value & "')"

func parseFloatIn*(v: string, lo, hi: float, x: var float): bool =
  ## A number from `lo` up to `hi` (both included), not NaN or infinite.
  try:
    x = parseFloat(v)
  except ValueError:
    return false
  x == x and x >= lo and x <= hi and classify(x) notin {fcInf, fcNegInf}

func parseIntIn*(v: string, lo, hi: int, n: var int): bool =
  try:
    n = parseInt(v)
  except ValueError:
    return false
  n >= lo and n <= hi

# Building options.  The field is named in the template and so is a plain field access: the proc
# made is an ordinary one (no closure), as `Apply` needs.

template flag*(P: typedesc, nameList: openArray[string], field: untyped): Opt[P] =
  ## An option without a value, which sets a bool field.
  Opt[P](
    names: @nameList,
    takesValue: false,
    apply: proc(p: var P, name, value: string): string {.nimcall, raises: [].} =
      p.field = true
      "",
  )

template text*(P: typedesc, nameList: openArray[string], field: untyped): Opt[P] =
  ## An option with a value that is kept as it is.
  Opt[P](
    names: @nameList,
    takesValue: true,
    apply: proc(p: var P, name, value: string): string {.nimcall, raises: [].} =
      p.field = value
      "",
  )

template number*(
    P: typedesc,
    nameList: openArray[string],
    field: untyped,
    lo, hi: float,
    what: string,
): Opt[P] =
  ## An option whose value is a number from `lo` to `hi`; `what` ("a number above 0") is
  ## for the message.
  Opt[P](
    names: @nameList,
    takesValue: true,
    apply: proc(p: var P, name, value: string): string {.nimcall, raises: [].} =
      var x = 0.0
      if not parseFloatIn(value, lo, hi, x):
        return valueIs(name, what, value)
      p.field = x
      "",
  )

template whole*(
    P: typedesc, nameList: openArray[string], field: untyped, lo, hi: int, what: string
): Opt[P] =
  ## An option whose value is a whole number from `lo` to `hi`.
  Opt[P](
    names: @nameList,
    takesValue: true,
    apply: proc(p: var P, name, value: string): string {.nimcall, raises: [].} =
      var n = 0
      if not parseIntIn(value, lo, hi, n):
        return valueIs(name, what, value)
      p.field = n
      "",
  )

template custom*(
    P: typedesc, nameList: openArray[string], takes: bool, body: untyped
): Opt[P] =
  ## An option with its own handling: `body` sees `p`, `name` and `value` and gives the problem
  ## (a string; "" for none) as its last expression.
  Opt[P](
    names: @nameList,
    takesValue: takes,
    apply: proc(
        p {.inject.}: var P, name {.inject.}, value {.inject.}: string
    ): string {.nimcall, raises: [].} =
      body,
  )

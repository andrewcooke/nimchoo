## The shared piece of the editable types (dev/editable-objects.md): a type declares its attributes once (`Kind`), and its
## command's options, their help, the parse of what is asked (`Action`: list, `--add NAME`, `--edit NAME`, `--delete`),
## applying the values given, and the table are made from that.  Reading and writing the type's tables stays with its
## package.

import std/[options, sequtils, strutils]
import ../../core/[line, optdoc]
import ../ui/[markup, vocabulary]
import ../util/args/args
import ../subject/steps
import ../../core/ruled

{.push raises: [].}

type
  Raw*[T] = object
    ## What the options fill in.  `steps` is for a type that is also a subject (its command adds `subject/stepOptions`).
    help*: bool
    kind*: Kind[T]
      ## the declaration (the parse is made of plain procs: they read it here)
    add*, edit*, base*, rename*: Option[string]
    delete*: bool
    names*: seq[string] ## `--names`: patterns of names
    namesGiven*: bool
    draft*: T ## the values given, on a blank `T`
    given*: seq[string] ## the options of the attributes given (`--gamma`), in order
    steps*: Steps

  Attr*[T] = object
    ## An attribute: its option, how it is copied from the values given, and its column.
    opt*: Opt[Raw[T]]
    copy*: proc(dst: var T, src: T) {.nimcall, noSideEffect, raises: [].}
    heading*: string ## with its unit: "max_gap_s"
    show*: proc(t: T): Line {.nimcall, noSideEffect, raises: [].}
    right*: bool ## the column is aligned to the right (numbers)

  Kind*[T] = object ## An editable type, declared once.
    one*, many*: string ## "model", "models"
    attrs*: seq[Attr[T]]
    nameOf*: proc(t: T): string {.nimcall, noSideEffect, raises: [].}
    rename*: proc(t: var T, name: string) {.nimcall, noSideEffect, raises: [].}
    nameProblem*:
      proc(text: string): Option[string] {.nimcall, noSideEffect, raises: [].}
      ## what is wrong with a text as a name (none if nothing is)
    patternProblem*:
      proc(text: string): Option[string] {.nimcall, noSideEffect, raises: [].}
      ## the same for a pattern of names
    check*: proc(t: T): Option[string] {.nimcall, noSideEffect, raises: [].}
      ## what is wrong with a whole thing (the rules beyond each attribute's)
    names*: Completion ## what completes a name

  ActionKind* = enum
    akList ## show them (the names, or a selection)
    akAdd
    akEdit
    akDelete

  Action*[T] = object ## What is asked, valid as far as the command line can say.
    draft*: T
    given*: seq[string]
    names*: seq[string] ## patterns, each valid (`akList`, `akDelete`)
    case kind*: ActionKind
    of akList, akDelete:
      discard
    of akAdd:
      name*: string
      base*: Option[string]
        ## the one copied (none: the type's blank, which the command fills)
    of akEdit:
      target*: string
      newName*: Option[string]

# The options.  Each is a plain proc (as `Apply` needs), generic in the type.

proc takeAdd[T](p: var Raw[T], name, value: string): Problem {.nimcall, raises: [].} =
  p.add = some(value)
  fine

proc takeBase[T](p: var Raw[T], name, value: string): Problem {.nimcall, raises: [].} =
  p.base = some(value)
  fine

proc takeEdit[T](p: var Raw[T], name, value: string): Problem {.nimcall, raises: [].} =
  p.edit = some(value)
  fine

proc takeRename[T](
    p: var Raw[T], name, value: string
): Problem {.nimcall, raises: [].} =
  p.rename = some(value)
  fine

proc takeDelete[T](
    p: var Raw[T], name, value: string
): Problem {.nimcall, raises: [].} =
  p.delete = true
  fine

proc takeNames[T](
    p: var Raw[T], name: string, values: seq[string]
): Problem {.nimcall, raises: [].} =
  if values.len == 0:
    return refuse(~"`{name}` needs a pattern")
  p.names.add values
  p.namesGiven = true
  fine

func one[T](
    names: openArray[string],
    apply: Apply[Raw[T]],
    metavar: string,
    help: Line,
    completion = Completion(),
): Opt[Raw[T]] =
  Opt[Raw[T]](
    names: @names,
    arity: (if metavar.len > 0: aOne else: aFlag),
    apply: apply,
    metavar: metavar,
    help: help,
    completion: completion,
  )

func options*[T](kind: Kind[T]): seq[Opt[Raw[T]]] =
  ## The options of the type's command, in the order of its usage: the names to list, the actions, then the attributes.
  result = @[
    listOption[Raw[T]](
      ["--names"],
      takeNames[T],
      "PATTERN...",
      ~"the {kind.many} with any of these names (case and accents aside; `*` is anything: `cycling:*`)",
      completion = kind.names,
    ),
    one[T](
      ["--add"],
      takeAdd[T],
      "NAME",
      ~"make a {kind.one} called NAME, with the values given below",
    ),
    one[T](
      ["--base"],
      takeBase[T],
      "NAME",
      ~"(with `--add`) copy the values of that {kind.one}, then use those given",
      kind.names,
    ),
    one[T](
      ["--edit"],
      takeEdit[T],
      "NAME",
      ~"change that {kind.one}: the values given below, or `--rename`",
      kind.names,
    ),
    one[T](["--rename"], takeRename[T], "NEW", ~"(with `--edit`) the new name"),
    one[T](
      ["--delete"],
      takeDelete[T],
      "",
      ~"delete the {kind.many} listed (with no criteria, the selection).  It asks first, saying which (`-y` answers yes)",
    ),
  ]
  for a in kind.attrs:
    result.add a.opt

# What the type's package writes for each attribute.

template valueAttr*(
    T: typedesc,
    optName: static string,
    field: untyped,
    metavarText: string,
    helpLine: Line,
    headingText: string,
    parseValue: untyped,
    showValue: untyped,
    rightAligned = true,
    unitText = "",
): Attr[T] =
  ## An attribute with one value: `parseValue(name, value, x: var F): Problem` reads it into `x` (the field's type), and
  ## `showValue(x): string` writes it in the table.  `unitText`: what a bare number is taken to have, after asking.
  Attr[T](
    opt: Opt[Raw[T]](
      names: @[optName],
      arity: aOne,
      apply: proc(p: var Raw[T], name, value: string): Problem {.nimcall, raises: [].} =
        var x: typeof(p.draft.field)
        let why = parseValue(name, value, x)
        if why.isSome:
          return why
        p.draft.field = x
        p.given.add optName
        fine,
      metavar: metavarText,
      help: helpLine,
      level: 1,
      unit: unitText,
    ),
    copy: proc(dst: var T, src: T) {.nimcall, noSideEffect, raises: [].} =
      dst.field = src.field,
    heading: headingText,
    show: proc(t: T): Line {.nimcall, noSideEffect, raises: [].} =
      plain(showValue(t.field)),
    right: rightAligned,
  )

template listAttr*(
    T: typedesc,
    optName: static string,
    field: untyped,
    metavarText: string,
    helpLine: Line,
    headingText: string,
    parseValue: untyped,
    showValue: untyped,
): Attr[T] =
  ## An attribute with any number of values (none is a value: `--tags` alone clears them): `parseValue(name, values, x:
  ## var F): Problem` and `showValue(x): Line`.
  Attr[T](
    opt: Opt[Raw[T]](
      names: @[optName],
      arity: aList,
      applyList: proc(
          p: var Raw[T], name: string, values: seq[string]
      ): Problem {.nimcall, raises: [].} =
        var x: typeof(p.draft.field)
        let why = parseValue(name, values, x)
        if why.isSome:
          return why
        p.draft.field = x
        p.given.add optName
        fine,
      metavar: metavarText,
      help: helpLine,
      level: 1,
    ),
    copy: proc(dst: var T, src: T) {.nimcall, noSideEffect, raises: [].} =
      dst.field = src.field,
    heading: headingText,
    show: proc(t: T): Line {.nimcall, noSideEffect, raises: [].} =
      showValue(t.field),
    right: false,
  )

# What is asked.

func actionOf*[T](raw: Raw[T]): Parsed[Action[T]] =
  ## The action the options ask for, or what is wrong with them.  (The values given are checked against the rest of the
  ## thing only when it is made: `made`, `edited` and `Kind.check`.)
  let kind = raw.kind
  func bad(why: Line): Parsed[Action[T]] =
    problemWith[Action[T]](why)

  let actions = [raw.add.isSome, raw.edit.isSome, raw.delete].countIt(it)
  if actions > 1:
    return bad(~"`--add`, `--edit` and `--delete` are one at a time")
  if raw.base.isSome and raw.add.isNone:
    return bad(~"`--base` goes with `--add NAME`")
  if raw.rename.isSome and raw.edit.isNone:
    return bad(~"`--rename` goes with `--edit NAME`")
  let changing = raw.add.isSome or raw.edit.isSome
  if raw.given.len > 0 and not changing:
    let first = raw.given[0]
    return bad(
      ~"`{first}` is a value for a {kind.one} made with `--add NAME` or changed with `--edit NAME`"
    )
  if raw.namesGiven and changing:
    return bad(
      ~"`--names` chooses the {kind.many} to list or delete: it does not go with `--add` or `--edit`"
    )
  for n in raw.names:
    let why = kind.patternProblem(n)
    if why.isSome:
      return bad(plain(why.get))
  for n in [raw.add, raw.rename].filterIt(it.isSome):
    let why = kind.nameProblem(n.get)
    if why.isSome:
      return bad(plain(why.get))
  if raw.add.isSome:
    parsedOk(
      Action[T](
        kind: akAdd,
        draft: raw.draft,
        given: raw.given,
        name: raw.add.get,
        base: raw.base,
      )
    )
  elif raw.edit.isSome:
    if raw.given.len == 0 and raw.rename.isNone:
      return bad(
        ~"`--edit NAME` changes the values given after it (or `--rename NEW`): none were given"
      )
    parsedOk(
      Action[T](
        kind: akEdit,
        draft: raw.draft,
        given: raw.given,
        target: raw.edit.get,
        newName: raw.rename,
      )
    )
  elif raw.delete:
    parsedOk(Action[T](kind: akDelete, names: raw.names))
  else:
    parsedOk(Action[T](kind: akList, names: raw.names))

func withGiven[T](kind: Kind[T], start: T, a: Action[T]): T =
  result = start
  for g in a.given:
    for at in kind.attrs:
      if g in at.opt.names:
        at.copy(result, a.draft)

func made*[T](kind: Kind[T], a: Action[T], base: T): T =
  ## The thing `--add` makes: the values of `base`, then those given, called by the name given.  (`kind.check` says
  ## whether it can be.)
  doAssert a.kind == akAdd
  result = kind.withGiven(base, a)
  kind.rename(result, a.name)

func edited*[T](kind: Kind[T], a: Action[T], old: T): T =
  ## What `--edit` makes of `old`: the values given, and the new name if there is one.
  doAssert a.kind == akEdit
  result = kind.withGiven(old, a)
  if a.newName.isSome:
    kind.rename(result, a.newName.get)

# The table.

func table*[T](
    kind: Kind[T], things: seq[T], selected: seq[bool], width: int, marks: bool
): seq[Line] =
  ## The things as a table (`core/ruled`): the name, then each attribute.  A selected one is a band in the selection's
  ## style (with `marks`, where there is no colour, in brackets too).  No lines if there are none.
  if things.len == 0:
    return
  var header = @[kind.one]
  var right: set[0 .. 31]
  for k, a in kind.attrs:
    header.add a.heading
    if a.right:
      right.incl k + 1
  var cells: seq[seq[Line]]
  var styles: seq[seq[StyleName]]
  for k, t in things:
    var row = @[plain(kind.nameOf(t))]
    for a in kind.attrs:
      row.add a.show(t)
    cells.add row
    styles.add(
      if selected[k]:
        @[selectedStyle]
      else:
        @[]
    )
  for l in ruledRows(
    header, cells, width, right = right, rowStyles = styles, alternate = false
  ):
    result.add(
      if marks:
        bracketed(l.line, l.row >= 0 and selected[l.row])
      else:
        l.line
    )

func sayList*(names: openArray[string]): string =
  ## "a, b and c"
  if names.len <= 1:
    names.join("")
  else:
    names[0 ..^ 2].join(", ") & " and " & names[^1]

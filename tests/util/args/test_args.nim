import std/[options, unittest]
import nimchoo/packages/util/args/args

func `==`(p: Problem, said: string): bool =
  ## (the tests say what a problem is, in words; no problem is "")
  p.get("") == said

type P = object
  verbose: bool
  name: string
  n: int
  x: float
  extra: seq[string]

let spec = Spec[P](
  opts: @[
    flag(P, ["-v", "--verbose"], verbose, "more"),
    text(P, ["--name"], name, "NAME", "the name"),
    whole(P, ["-n", "--count"], n, 1, 10, "a number of times, 1 to 10", "N", "how many"),
    number(P, ["--x"], x, 0.0, 1.0, "a fraction", "X", "a fraction"),
  ],
  positional: proc(p: var P, arg: string): Problem {.nimcall, raises: [].} =
    if arg == "bad":
      return refuse("no 'bad' please")
    p.extra.add arg
    fine,
)

suite "cli args: one parser for the commands":
  test "flags, values and positional arguments, in any order":
    var p = P()
    check parseOptions(
      @["a", "-v", "--name", "bob", "b", "--count", "3", "--x", "0.5"], spec, p
    ) == ""
    check p.verbose and p.name == "bob" and p.n == 3 and p.x == 0.5 and
      p.extra == @["a", "b"]
  test "a missing value is named":
    var p = P()
    check parseOptions(@["--name"], spec, p) == "--name needs a value"
    check parseOptions(@["-n"], spec, p) == "-n needs a value"
  test "a bad value says what is wanted, with the option as spelt":
    var p = P()
    check parseOptions(@["-n", "11"], spec, p) ==
      "-n is a number of times, 1 to 10 (not '11')"
    check parseOptions(@["--count", "x"], spec, p) ==
      "--count is a number of times, 1 to 10 (not 'x')"
    check parseOptions(@["--x", "nan"], spec, p) == "--x is a fraction (not 'nan')"
    check parseOptions(@["--x", "inf"], spec, p) == "--x is a fraction (not 'inf')"
    check parseOptions(@["--x", "1.5"], spec, p) == "--x is a fraction (not '1.5')"
  test "the first problem is the one reported":
    var p = P()
    check parseOptions(@["--bogus", "-n", "99"], spec, p) == "unexpected option --bogus"
  test "an unknown option, and a positional argument that the command refuses":
    var p = P()
    check parseOptions(@["--bogus"], spec, p) == "unexpected option --bogus"
    check parseOptions(@["bad"], spec, p) == "no 'bad' please"
  test "a lone dash is an argument, not an option":
    var p = P()
    check parseOptions(@["-"], spec, p) == ""
    check p.extra == @["-"]
  test "without positional arguments they are unexpected, with the hint if there is one":
    let bare = Spec[P](opts: @[flag(P, ["-v"], verbose, "more")])
    var p = P()
    check parseOptions(@["x"], bare, p) == "unexpected argument x"
    let hinted = Spec[P](
      opts: bare.opts,
      hint: proc(arg: string): string {.nimcall, raises: [].} =
        " (try --name " & arg & ")",
    )
    check parseOptions(@["x"], hinted, p) == "unexpected argument x (try --name x)"
  test "no arguments is fine":
    var p = P()
    check parseOptions(@[], spec, p) == ""

suite "cli args: --name=value, leading options, options with many values":
  test "--name=value is --name value":
    var p = P()
    check parseOptions(@["--name=bob", "--count=4"], spec, p) == ""
    check p.name == "bob" and p.n == 4
    check parseOptions(@["--name="], spec, p) == "" # (an empty value is a value)
    check p.name == ""
    check parseOptions(@["--count=11"], spec, p) ==
      "--count is a number of times, 1 to 10 (not '11')"
    check parseOptions(@["--verbose=1"], spec, p) == "--verbose does not take a value"
    check parseOptions(@["--bogus=1"], spec, p) == "unexpected option --bogus=1"
  test "leading options stop at the first argument that is not one":
    var p = P()
    var next = 0
    check parseLeading(@["-v", "--name", "bob", "cmd", "-n", "3"], spec, p, next) == ""
    check next == 3 and p.verbose and p.name == "bob" and p.n == 0
    check parseLeading(@["-v"], spec, p, next) == "" and next == 1 # (no command)
    check parseLeading(@["cmd"], spec, p, next) == "" and next == 0
    check parseLeading(@["--bogus", "cmd"], spec, p, next) == "unexpected option --bogus"
  test "an option with many values takes the words up to the next option":
    let many = Spec[P](
      opts: @[
        listOption[P](
          ["--names"],
          proc(
              p: var P, name: string, values: seq[string]
          ): Problem {.nimcall, raises: [].} =
            if values.len == 0:
              return refuse(name & " needs at least one name")
            p.extra.add values
            fine,
          "NAME...",
          "names",
        ),
        flag(P, ["-v"], verbose, "more"),
      ]
    )
    var p = P()
    check parseOptions(@["--names", "a", "b", "-v", "--names", "c"], many, p) == ""
    check p.extra == @["a", "b", "c"] and p.verbose
    check parseOptions(@["--names"], many, p) == "--names needs at least one name"
    check parseOptions(@["--names", "-v"], many, p) == "--names needs at least one name"
    check parseOptions(@["--names=x"], many, p) == ""
    check p.extra == @["a", "b", "c", "x"]

suite "cli args: the options every command has":
  test "--user and --db after the command say where they go":
    var p = P()
    check parseOptions(@["-v", "--user", "bob"], spec, p) ==
      "unexpected option --user (it goes before the command: nch --user NAME COMMAND ...)"
    check parseOptions(@["--db=x.db"], spec, p) ==
      "unexpected option --db=x.db (it goes before the command: nch --db PATH COMMAND ...)"
    check parseOptions(@["--users"], spec, p) == "unexpected option --users"
      # (another option: no hint)

suite "cli args: what a command line comes to":
  type Q = object
    help: bool
    n: int

  let qspec =
    Spec[Q](opts: @[whole(Q, ["-n"], n, 1, 9, "a digit", "N", "a number"), helpFlag(Q)])
  func finishQ(raw: Q): Parsed[int] =
    if raw.n == 5:
      return problemWith[int]("five is too many")
    parsedOk(raw.n)

  test "valid parameters, a request for help, or a problem":
    let ok = parseCommand(@["-n", "3"], qspec, Q(), finishQ)
    check ok.kind == pkOk and ok.params == 3 and ok.problem == "" and not ok.help
    let help = parseCommand(@["-h"], qspec, Q(), finishQ)
    check help.kind == pkHelp and help.help
    let bad = parseCommand(@["-n", "x"], qspec, Q(), finishQ)
    check bad.kind == pkProblem and bad.problem == "-n is a digit (not 'x')"
    let combination = parseCommand(@["-n", "5"], qspec, Q(), finishQ)
    check combination.problem == "five is too many"

  test "an option has a level, and is allowed in an address if it says so":
    let o = flag(Q, ["--deep"], help, "nested", level = 1, address = adFlag)
    check o.level == 1 and o.address == adFlag and o.doc.level == 1
    check flag(Q, ["--plain"], help, "no address").address == adNo

suite "cli args: an option whose value may be left out":
  type O = object
    help: bool
    shell: string
    verbose: bool

  let ospec = Spec[O](
    opts: @[
      optionalValue(
        O,
        ["--shell"],
        "SHELL",
        "which shell",
        body = (p.shell = (if value.len == 0: "bash" else: value); fine),
      ),
      flag(O, ["-v"], verbose, "talk"),
      helpFlag(O),
    ]
  )

  test "the next word is the value; with none, or an option next, it is left out":
    var p = O()
    check parseOptions(@["--shell", "zsh"], ospec, p) == fine and p.shell == "zsh"
    p = O()
    check parseOptions(@["--shell"], ospec, p) == fine and p.shell == "bash"
    p = O()
    check parseOptions(@["--shell", "-v"], ospec, p) == fine
    check p.shell == "bash" and p.verbose
    p = O()
    check parseOptions(@["--shell=fish"], ospec, p) == fine and p.shell == "fish"

  test "at the start of a command line the value is taken, and the rest is the command":
    var p = O()
    var next = 0
    check parseLeading(@["--shell", "zsh", "climbs"], ospec, p, next) == fine
    check p.shell == "zsh" and next == 2

  test "it describes itself as optional":
    check ospec.docs[0].arity == aOptional

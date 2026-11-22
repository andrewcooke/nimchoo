import std/[options, strutils, unittest]
import nimchoo/core/[globals, line, unitfix]

let fix = UnitFix(
  missing: @[Unitless(option: "--radius", value: "3", unit: "km")],
  original: @["--from", "Las Condes", "--radius", "3"],
  args: @["--from", "Las Condes", "--radius", "3km"],
)

func emphasised(l: Line): string =
  ## The text with what is in `em` between brackets.
  for sp in l:
    if sp.styles == @[styleName"em"]:
      result.add "[" & sp.text & "]"
    else:
      result.add sp.text

func keys(typed: string): proc(): Option[char] {.raises: [].} =
  ## (keys pressed, one at a time; then the input ends)
  var at = 0
  result = proc(): Option[char] {.raises: [].} =
    if at < typed.len:
      inc at
      some(typed[at - 1])
    else:
      none(char)

suite "unitfix: a number with no unit, and the question":
  test "the command line is written again, each argument quoted, the added unit in em":
    check commandLine(@[], "nch activities", fix).plainText ==
      "nch activities --from 'Las Condes' --radius 3km"
    check commandLine(@[], "nch activities", fix).emphasised ==
      "nch activities --from 'Las Condes' --radius 3[km]"
    check commandLine(@[], "nch log", UnitFix()).plainText == "nch log"
  test "every unit that was filled in is in em, and nothing else; the quotes go round the whole argument":
    let range = UnitFix(
      original: @["--distance", "10-50km", "--names", "a b"],
      args: @["--distance", "10km-50km", "--names", "a b"],
    )
    check commandLine(@[], "nch activities", range).emphasised ==
      "nch activities --distance 10[km]-50km --names 'a b'"
    let quoted =
      UnitFix(original: @["--from=Las Condes ~5"], args: @["--from=Las Condes ~5km"])
    check commandLine(@[], "nch activities", quoted).emphasised ==
      "nch activities '--from=Las Condes ~5[km]'"
    let eq = UnitFix(original: @["--radius=3"], args: @["--radius=3km"])
    check commandLine(@[], "nch activities", eq).emphasised ==
      "nch activities --radius=3[km]"
    let below =
      UnitFix(original: @["--distance", "42km~200"], args: @["--distance", "42km~200m"])
    check commandLine(@[], "nch activities", below).emphasised ==
      "nch activities --distance '42km~200[m]'"
  test "the options before the command are kept":
    let f = UnitFix(original: @["--radius", "3"], args: @["--radius", "3km"])
    check commandLine(@["--offline", "--db", "/my dir/x.db"], "nch activities", f).plainText ==
      "nch --offline --db '/my dir/x.db' activities --radius 3km"
  test "the question is two lines: warn, then the command line with the unit in em":
    let g = Globals(leading: @["--offline"])
    let q = questionLines(g.leading, "nch activities", fix)
    check q.len == 2
    check q[0].plainText == "nch activities: --radius 3 is missing a unit; did you mean"
    check q[0][0].styles == @[styleName"warn"]
    check q[1].plainText == "> nch --offline activities --from 'Las Condes' --radius 3km"
    check q[1].emphasised.endsWith("--radius 3[km]")
    check q[1][0].text == ">" and q[1][0].styles == @[styleName"warn"]
  test "several options are named together":
    var two = fix
    two.missing.add Unitless(option: "--distance", value: "40", unit: "km")
    check questionLines(@[], "nch activities", two)[0].plainText ==
      "nch activities: --radius 3, --distance 40 are missing units; did you mean"
  test "on a terminal, Enter or y or Y means yes, and the corrected arguments come back":
    let g = Globals(offline: true)
    for yes in ["\r", "\n", "y", "Y", "xyz y"]:
      check askUnit(g, "nch activities", fix, true, keys(yes)) == some(fix.args)
  test "n, N, Ctrl-C, Ctrl-D and the end of the input mean no; other keys wait":
    let g = Globals(offline: true)
    for no in ["n", "N", "\3", "\4", "", "x1 n", "xz"]:
      check askUnit(g, "nch activities", fix, true, keys(no)).isNone
  test "with -y the corrected arguments come back at once, without a key":
    let g = Globals(offline: true)
    var yes = fix
    yes.yes = true
    check askUnit(g, "nch activities", yes, false, keys("")) == some(fix.args)
  test "not on a terminal, nothing is asked and it fails":
    let g = Globals(offline: true)
    var asked = false
    let reader = proc(): Option[char] {.raises: [].} =
      asked = true
      some('y')
    check askUnit(g, "nch activities", fix, false, reader).isNone
    check not asked

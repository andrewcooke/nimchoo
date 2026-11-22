import std/[options, unittest]
import nimchoo/core/[globals, line, unitfix]

let fix = UnitFix(
  missing: @[Unitless(option: "--radius", value: "3", unit: "km")],
  args: @["--from", "Las Condes", "--radius", "3km"],
)

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
  test "the command line is written again, each argument quoted":
    check commandLine(@[], "nch activities", fix.args) ==
      "nch activities --from 'Las Condes' --radius 3km"
    check commandLine(@[], "nch log", @[]) == "nch log"
  test "the options before the command are kept":
    check commandLine(
      @["--offline", "--db", "/my dir/x.db"], "nch activities", @["--radius", "3km"]
    ) == "nch --offline --db '/my dir/x.db' activities --radius 3km"
  test "the question is two lines, in warn and default; the choice follows the command on a terminal":
    let g = Globals(leading: @["--offline"])
    let q = questionLines(g.leading, "nch activities", fix)
    check q.len == 2
    check q[0].plainText == "nch activities: --radius 3 has no unit; did you mean"
    check q[0][0].styles == @[styleName"warn"]
    check q[1].plainText == "  nch --offline activities --from 'Las Condes' --radius 3km"
    check q[1][0].styles.len == 0
  test "several options are named together":
    var two = fix
    two.missing.add Unitless(option: "--distance", value: "40", unit: "km")
    check questionLines(@[], "nch activities", two)[0].plainText ==
      "nch activities: --radius 3, --distance 40 have no unit; did you mean"
  test "on a terminal, Enter or y or Y means yes, and the corrected arguments come back":
    let g = Globals(offline: true)
    for yes in ["\r", "\n", "y", "Y", "xyz y"]:
      check askUnit(g, "nch activities", fix, true, keys(yes)) == some(fix.args)
  test "n, N, Ctrl-C, Ctrl-D and the end of the input mean no; other keys wait":
    let g = Globals(offline: true)
    for no in ["n", "N", "\3", "\4", "", "x1 n", "xz"]:
      check askUnit(g, "nch activities", fix, true, keys(no)).isNone
  test "not on a terminal, nothing is asked and it fails":
    let g = Globals(offline: true)
    var asked = false
    let reader = proc(): Option[char] {.raises: [].} =
      asked = true
      some('y')
    check askUnit(g, "nch activities", fix, false, reader).isNone
    check not asked

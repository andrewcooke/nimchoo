import std/[options, unittest]
import nimchoo/core/[globals, line, unitfix]

let fix = UnitFix(
  missing: @[Unitless(option: "--radius", value: "3", unit: "km")],
  args: @["--from", "Las Condes", "--radius", "3km"],
)

func says(text: string): proc(): Option[string] {.raises: [].} =
  ## (an answer typed)
  result = proc(): Option[string] {.raises: [].} =
    some(text)

let noAnswer = proc(): Option[string] {.raises: [].} =
  none(string)

suite "unitfix: a number with no unit, and the question":
  test "the command line is written again, each argument quoted":
    check commandLine("nch activities", fix.args) ==
      "nch activities --from 'Las Condes' --radius 3km"
    check commandLine("nch log", @[]) == "nch log"
  test "the question is in three styles: warn, default and em":
    let q = questionLines("nch activities", fix)
    check q.len == 3
    check q[0].plainText == "nch activities: --radius 3 has no unit; did you mean"
    check q[0][0].styles == @[styleName"warn"]
    check q[1].plainText == "  nch activities --from 'Las Condes' --radius 3km"
    check q[1][0].styles.len == 0
    check q[2].plainText == "[Yn] "
    check q[2][0].styles == @[styleName"em"]
  test "several options are named together":
    var two = fix
    two.missing.add Unitless(option: "--distance", value: "40", unit: "km")
    check questionLines("nch activities", two)[0].plainText ==
      "nch activities: --radius 3, --distance 40 have no unit; did you mean"
  test "on a terminal, Enter or y or yes means yes, and the corrected arguments come back":
    let g = Globals(offline: true)
    for yes in ["", "y", "Y", "yes", " y "]:
      check askUnit(g, "nch activities", fix, true, says(yes)) == some(fix.args)
  test "anything else, or the input ending, means no":
    let g = Globals(offline: true)
    for no in ["n", "N", "no", "x", "3"]:
      check askUnit(g, "nch activities", fix, true, says(no)).isNone
    check askUnit(g, "nch activities", fix, true, noAnswer).isNone
  test "not on a terminal, nothing is asked and it fails":
    let g = Globals(offline: true)
    var asked = false
    let reader = proc(): Option[string] {.raises: [].} =
      asked = true
      some("y")
    check askUnit(g, "nch activities", fix, false, reader).isNone
    check not asked

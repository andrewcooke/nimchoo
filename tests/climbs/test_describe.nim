import std/unittest
import nimchoo/packages/climbs/describe

let san = ClimbInfo(
  name: "Cerro San Luis₄", category: "4", lengthM: 500.0, gainM: 89.4, gradient: 17.8
)

suite "climbs: saying a climb":
  test "the line: name, category, length, gain, gradient":
    check climbLine(san) == "Cerro San Luis₄  4 0.5km +89m 17.8%"
  test "the cells, to be lined up":
    check climbCells(san) == @["Cerro San Luis₄", "4", "0.5km", "+89m", "17.8%"]
  test "a big one":
    check climbLine(
      ClimbInfo(
        name: "Farellones₁",
        category: "HC",
        lengthM: 16710.0,
        gainM: 1211.0,
        gradient: 7.2,
      )
    ) == "Farellones₁  HC 16.7km +1211m 7.2%"
  test "no category is a dash":
    check climbLine(
      ClimbInfo(name: "unnamed", lengthM: 1400.0, gainM: 80.0, gradient: 5.8)
    ) == "unnamed  - 1.4km +80m 5.8%"
  test "the pieces: the gain rounded, a plus sign; the gradient to a tenth":
    check gainText(89.5) == "+90m" and gainText(89.4) == "+89m" and
      gainText(0.0) == "+0m"
    check gradientText(17.84) == "17.8%" and gradientText(5.0) == "5.0%"

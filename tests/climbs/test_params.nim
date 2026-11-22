import std/[options, strutils, unittest]
import nimchoo/packages/climbs/params
import nimchoo/packages/confirm/confirm
import nimchoo/packages/util/args/args

suite "climbs: the command line":
  test "no arguments: the climbs selection; --all: every climb":
    let p = parseArgs(@[])
    check p.problem.len == 0 and p.params.action == caList and
      p.params.list.kind == lkSelection
    let a = parseArgs(@["--all"])
    check a.problem.len == 0 and a.params.action == caList and
      a.params.list.kind == lkFound and not a.params.list.criteria.given and
      not a.params.list.select
  test "rename and auto":
    let r = parseArgs(@["--edit", "Morro La Cabra₁", "--rename", "  La Cabra  "])
    check r.problem.len == 0 and r.params.action == caEdit and
      r.params.edit.climb == "Morro La Cabra₁"
    check r.params.edit.change.kind == ckRename and
      r.params.edit.change.newName == "La Cabra"
    let a = parseArgs(@["--edit", "X", "--auto"])
    check a.problem.len == 0 and a.params.edit.change.kind == ckAuto
  test "mistakes":
    check parseArgs(@["--edit", "X"]).problem.contains("something to change")
    check parseArgs(@["--edit", "X", "--rename", "Y", "--auto"]).problem.contains(
      "cannot be used together"
    )
    check parseArgs(@["--rename", "Y"]).problem.contains("go with `--edit NAME`")
    check parseArgs(@["--auto"]).problem.contains("go with `--edit NAME`")
    check parseArgs(@["--edit", " ", "--auto"]).problem.contains("needs the name")
    check parseArgs(@["Cerro"]).problem.contains("`--edit Cerro --rename NEW`")
  test "names that are refused":
    check nameProblem("Cerro Calán") == ""
    check nameProblem("  ").contains("empty")
    check nameProblem("x".repeat(61)).contains("at most")
    check nameProblem("a\nb").contains("control")
    check nameProblem("Cuesta₂").contains("subscript")
    check nameProblem("Cuesta (the 2/3 one)") == ""
    check parseArgs(@["--edit", "X", "--rename", "Cuesta₂"]).problem.contains(
      "subscript"
    )
  test "an old-style (n/m) at the end is just text now":
    check nameProblem("Cuesta (2/3)") == ""

suite "climbs: retiring":
  test "retire and unretire go with --edit; --retired and --duplicates are lists":
    check parseArgs(@["--edit", "X₂", "--retire"]).params.edit.change.kind == ckRetire
    check parseArgs(@["--edit", "X₂", "--unretire"]).params.edit.change.kind ==
      ckUnretire
    check parseArgs(@["--retired"]).params.action == caRetired
    check parseArgs(@["--duplicates"]).params.action == caDuplicates
    check parseArgs(@["--retire"]).problem.contains("go with `--edit NAME`")
    check parseArgs(@["--unretire"]).problem.contains("go with `--edit NAME`")
    check parseArgs(@["--edit", "X", "--retire", "--unretire"]).problem.contains(
      "cannot be used together"
    )
    check parseArgs(@["--edit", "X", "--retire", "--rename", "Y"]).problem.contains(
      "cannot be used together"
    )
    check parseArgs(@["--edit", "X"]).problem.contains("--retire")
    check parseArgs(@["--retired", "--duplicates"]).problem.contains(
      "cannot be used together"
    )
    check parseArgs(@["--all", "--retired"]).problem.contains("cannot be used together")
    check parseArgs(@["--edit", "X", "--retire", "--retired"]).problem.contains(
      "do not go with `--edit`"
    )
    check parseArgs(@["--edit", "X", "--retire", "--all"]).problem.contains(
      "do not go with `--edit`"
    )

suite "climbs params: --delete":
  test "--delete needs --all, and -f goes with it":
    let c = parseArgs(@["--all", "--delete", "-f"])
    check c.problem == "" and c.params.action == caDeleteAll and c.params.force == fYes
    check parseArgs(@["--all", "--delete", "-f", "-f"]).params.force == fNow
      # (twice: no pause)
    check parseArgs(@["--all", "--delete", "--force", "--force"]).params.force == fNow
    check parseArgs(@["--delete"]).problem.contains("needs `--all`")
    check parseArgs(@["--all", "-f"]).problem.contains("goes with `--delete`")
    check parseArgs(@["--all", "--delete", "--retired"]).problem.len > 0
    check parseArgs(@["--all", "--delete", "--edit", "X", "--retire"]).problem.len > 0

suite "climbs params: --names, -v, --everyone":
  test "names, and the flags":
    let c = parseArgs(@["--names", "farellones", "cuesta", "-v", "--everyone"])
    check c.problem == "" and c.params.action == caList and c.params.list.kind == lkFound
    check c.params.list.criteria.names == @["farellones", "cuesta"] and
      c.params.list.attempts.verbose and c.params.list.attempts.everyone
  test "--names needs text and goes with nothing that changes, or lists for tidying":
    check parseArgs(@["--names"]).problem.len > 0
    for o in [
      @["--retired"],
      @["--duplicates"],
      @["--delete", "--all"],
      @["--edit", "X", "--retire"],
    ]:
      check parseArgs(@["--names", "x"] & o).problem.len > 0
  test "-v and --everyone go with the attempts only (--all shows them too)":
    for o in [@["--retired"], @["--duplicates"], @["--edit", "X", "--retire"]]:
      check parseArgs(@["-v"] & o).problem.len > 0
      check parseArgs(@["--everyone"] & o).problem.len > 0
    check parseArgs(@["-v", "--all"]).problem == ""

suite "climbs params: criteria":
  test "each criterion is read, and they go together":
    let p = parseArgs(
      @[
        "--names", "Farellones", "62", "--ridden", "--from", "-33.42,-70.63",
        "--radius", "5km", "--categories", "hc", "1", "--select", "-v",
      ]
    )
    check p.problem == ""
    let l = p.params.list
    check l.kind == lkFound and l.select and l.attempts.verbose
    let c = l.criteria
    check c.names == @["Farellones", "62"] and c.ridden and c.categories == @["HC", "1"]
    check c.start.isSome and c.start.get.kind == nrPoint and c.start.get.lat == -33.42 and
      c.start.get.lon == -70.63 and c.startKm == 5.0 and c.passes.isNone

  test "--near takes a place's name, and the radius has a default":
    let c = parseArgs(@["--near", "Providencia"]).params.list.criteria
    check c.passes.get.kind == nrPlace and c.passes.get.place == "Providencia" and
      c.passKm == defaultPassKm and c.start.isNone
    check parseArgs(@["--from", "0,0"]).params.list.criteria.startKm == defaultStartKm

  test "the radius has its unit; with none it is the question, km added":
    let q = parseArgs(@["--near", "0,0", "--radius", "3"])
    check q.kind == pkUnit and q.fix.args == @["--near", "0,0", "--radius", "3km"]
    check parseArgs(@["--near", "0,0", "--radius", "500m"]).params.list.criteria.passKm ==
      0.5
    for bad in ["-1km", "nan", "3mi", "infkm"]:
      check parseArgs(@["--near", "0,0", "--radius", bad]).problem.contains("radius")

  test "--save is --select; --select keeps what --all finds too":
    check parseArgs(@["--ridden", "--save"]).params.list.select
    check parseArgs(@["--all", "--select"]).params.list.select

  test "mistakes":
    check parseArgs(@["--select"]).problem.contains("needs criteria or `--all`")
    check parseArgs(@["--invert"]).problem.contains("needs criteria")
    check parseArgs(@["--radius", "3"]).problem.contains(
      "goes with `--from` or `--near`"
    )
    check parseArgs(@["--near", "1x,2"]).problem.contains("cannot read the position")
    check parseArgs(@["--near", "0,0", "--radius", "0km"]).problem.contains(
      "more than 0"
    )
    check parseArgs(@["--near", "0,0", "--radius", "0"]).problem.contains("radius")
      # (a bare 0 is read as 0km, and refused: there is no use asking)
    check parseArgs(@["--categories", "5"]).problem.contains("not a category")
    check parseArgs(@["--ridden", "--retired"]).problem.contains("do not go with")
    check parseArgs(@["--ridden", "--edit", "X", "--retire"]).problem.contains(
      "do not go with"
    )

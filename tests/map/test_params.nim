import std/[options, sequtils, strutils, unittest]
import nimchoo/packages/map/params
import nimchoo/packages/util/args/args
import nimchoo/packages/web/webopts
import nimchoo/packages/web/request
import ../support/webpages

suite "map: the command line":
  test "no options: the current selection":
    let p = parseArgs(@[])
    check p.problem == "" and p.params.target == tSelection and
      p.params.web.kind == wkNone
  test "--selection and --state":
    let p = parseArgs(@["--selection", "AWAnLmgGhgZI6JjZom", "--state", "c3eef5"])
    check p.problem == "" and p.params.target == tList
    check p.params.selection == "AWAnLmgGhgZI6JjZom" and p.params.state == some(
      "c3eef5"
    )
    check parseArgs(@["--selection", "AWAnLmgGhgZI6JjZom"]).params.state.isNone
      # the check is optional
    check parseArgs(@["--selection", "A--B_"]).problem == ""
      # (two dashes in a row are allowed in a list)
  test "--layers: what is drawn, routes and climbs if it is not said":
    check parseArgs(@[]).params.layers == {lyRoutes, lyClimbs}
    check parseArgs(@["--layers", "heat"]).params.layers == {lyHeat}
    check parseArgs(@["--layers", "heat", "routes"]).params.layers == {lyRoutes, lyHeat}
    check parseArgs(@["--layers", "routes", "climbs", "heat", "heat"]).params.layers ==
      {lyRoutes, lyClimbs, lyHeat}
    check parseArgs(@["--layers", "heat", "--selection", "AWAn"]).params.layers ==
      {lyHeat}
  test "--layers: the gates and the efforts of the climbs":
    check parseArgs(@["--layers", "gates", "efforts"]).params.layers ==
      {lyGates, lyEfforts}
    check parseArgs(@["--layers", "routes", "climbs", "gates", "efforts"]).params.layers ==
      {lyRoutes, lyClimbs, lyGates, lyEfforts}
  test "--layers: the layers are words, separated by spaces":
    check parseArgs(@["--layers", "heat", "routes"]).params.layers == {lyRoutes, lyHeat}
    check parseArgs(@["--layers=heat"]).params.layers == {lyHeat}
  test "--layers problems: a name that is not a layer, or none":
    for bad in ["", "routs", "routes,", "heat,routes", "Heat"]:
      check parseArgs(@["--layers", bad]).problem.contains("is not a layer")
    check parseArgs(@["--layers", "heat", "routs"]).problem.contains("is not a layer")
    check parseArgs(@["--layers"]).problem.contains("needs at least one layer")
  test "the layers have one spelling, and parse back":
    check layersText({lyHeat, lyRoutes}) == "routes,heat"
    check layersText(defaultLayers) == "routes,climbs"
    for layers in [{lyRoutes}, {lyHeat}, {lyRoutes, lyClimbs, lyHeat}]:
      check parseLayers(layersText(layers).split(',')) == some(layers)
    check layerNames() == @["routes", "climbs", "heat", "gates", "efforts"]
  test "--worker":
    check parseArgs(@["--worker"]).params.web.kind == wkWorker
    check parseArgs(@["--worker", "--selection", "AWAn", "--state", "ab12"]).problem ==
      ""
  test "--web and its options":
    let p = parseArgs(@["--web", "--no-open", "--port", "0", "--new-token"])
    check p.problem == "" and p.params.web.kind == wkServe
    check p.params.web.noOpen and p.params.web.newToken and p.params.web.port == 0
    check parseArgs(@["--web"]).params.web.port == 62466
    check parseArgs(@["--web", "--port", "8080"]).params.web.port == 8080
  test "--web problems":
    check parseArgs(@["--web", "--worker"]).problem.contains("cannot be used together")
    for opt in [@["--no-open"], @["--new-token"], @["--port", "8080"]]:
      check parseArgs(opt).problem.contains("go with --web")
    for bad in ["x", "-1", "65536", "1.5", ""]:
      check parseArgs(@["--web", "--port", bad]).problem.contains("port number")
  test "problems":
    check parseArgs(@["--selection"]).problem.contains("needs a value")
    check parseArgs(@["--selection", "a b"]).problem.contains(
      "not a list of activities"
    )
    check parseArgs(@["--selection", "a+b"]).problem.contains(
      "not a list of activities"
    )
    check parseArgs(@["--selection", "AWAn", "--state", "XYZ"]).problem.contains(
      "not a state of activities"
    )
    check parseArgs(@["--state", "ab12"]).problem.contains("goes with --selection")
    check parseArgs(@["--style", "lines"]).problem.contains("unexpected")
      # (the old options are gone)
    check parseArgs(@["--tolerance", "5"]).problem.contains("unexpected")
    check parseArgs(@["--bogus"]).problem.contains("unexpected")
    check parseArgs(@["-h"]).help

suite "map: the page the server may run":
  test "it is made from the options marked as allowed in an address":
    check mapPage.command == "map"
    check mapPage.options.mapIt(it.name) == @["layers", "selection", "state"]
    check mapPage.flags.len == 0
  test "what it accepts in an address is what the options accept":
    let layers = mapPage.options[0].valid
      # (of one item: an address spells a list with commas)
    check mapPage.options[0].isList and not mapPage.options[1].isList
    check layers("routes") and layers("heat") and not layers("") and not layers("routs") and
      not layers("heat,routes")
    let bits = mapPage.options[1].valid
    check bits("AWAnLmgGhgZI6JjZom") and bits("A--B_") and not bits("") and
      not bits("a b")
    let hex = mapPage.options[2].valid
    check hex("c3eef5") and not hex("XYZ") and not hex("")

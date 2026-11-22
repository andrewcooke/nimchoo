import std/[options, strutils, unittest]
import nimchoo/packages/near/near
import nimchoo/packages/ui/units
import nimchoo/packages/util/args/args

func problemText(p: Problem): string =
  if p.isSome: p.get.plainText else: ""

suite "near: a point, a place or a reference, and the radius":
  test "a position, or a place's name; latest and previous only where there is a latest":
    check parseSpot("38.72,-9.14", false).get ==
      Spot(kind: nkPoint, lat: 38.72, lon: -9.14)
    check parseSpot(" Lo Barnechea ", false).get ==
      Spot(kind: nkPlace, place: "Lo Barnechea")
    check parseSpot("Latest", true).get.kind == nkLatest
    check parseSpot("PREVIOUS", true).get.kind == nkPrevious
    check parseSpot("latest", false).get == Spot(kind: nkPlace, place: "latest")
  test "what looks like a number is a position written wrongly":
    for bad in ["", "38.7", "1x,2", "91,0", "-5", "+1,2,3"]:
      check parseSpot(bad, true).isNone
  test "the radius is a distance with its unit, more than zero":
    var w: Where
    check takeRadius(w, "3km").problemText == "" and w.radius == some(Distance(3000.0))
    check takeRadius(w, "500m").problemText == "" and w.radius == some(Distance(500.0))
    for bad in ["3", "0km", "-1km", "nankm", "3mi", ""]:
      var x: Where
      check takeRadius(x, bad).problemText.contains("cannot read the radius")
      check x.radius.isNone
  test "each has its own default radius":
    check startKm(none(Distance)) == 10.0 and passKm(none(Distance)) == 1.0
    check startKm(some(Distance(2500.0))) == 2.5 and
      passKm(some(Distance(2500.0))) == 2.5
  test "a radius alone is from latest for the activities, and refused for the others":
    var w = Where(radius: some(Distance(3000.0)))
    check w.settle(true).problemText == "" and w.start.kind == nkLatest
    var x = Where(radius: some(Distance(3000.0)))
    check x.settle(false).problemText.contains("goes with `--from` or `--near`")
    var y =
      Where(radius: some(Distance(3000.0)), passes: Spot(kind: nkPlace, place: "a"))
    check y.settle(false).problemText == "" and y.start.kind == nkNone
    var z: Where
    check z.settle(false).problemText == "" and not z.hasPlace
  test "the help says what is searched, and has latest only where it is allowed":
    check nearHelp("the climbs", false)[0].plainText.startsWith("the climbs that start")
    check "latest" notin nearHelp("the climbs", false)[0].plainText
    check "latest" in nearHelp("activities", true)[0].plainText
    check "10km" in nearHelp("activities", true)[0].plainText
    check "1km" in nearHelp("activities", true)[1].plainText

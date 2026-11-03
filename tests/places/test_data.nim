import std/[options, unittest]
import nimchoo/places/data

suite "places data: reading a list":
  test "a place":
    let p = parsePlace("Valparaíso\tCL\t-33.036\t-71.62963\t296655").get
    check p.name == "Valparaíso" and p.country == "CL"
    check p.lat == -33.036 and p.lon == -71.62963 and p.population == 296655
  test "not a place":
    for bad in ["", "Valparaíso", "a\tCL\t1\t2", "a\tCL\t1\t2\t3\t4", "\tCL\t1\t2\t3", "a\tCHL\t1\t2\t3",
                "a\tC\t1\t2\t3", "a\tCL\tx\t2\t3", "a\tCL\t1\ty\t3", "a\tCL\t1\t2\tz",
                "a\tCL\t91\t2\t3", "a\tCL\t-91\t2\t3", "a\tCL\t1\t181\t3", "a\tCL\t1\t-181\t3"]:
      check parsePlace(bad).isNone
  test "a text of lines; the ones that are not places are left out":
    let rows = parsePlaces("A\tPT\t38.7\t-9.1\t100\n\nnonsense\nB\tFR\t48.8\t2.3\t200\n")
    check rows.len == 2 and rows[0].name == "A" and rows[1].country == "FR"
  test "gzipped or not":
    check unpack("plain text", false) == "plain text"
    check unpack("this is not gzip data", true) == ""        # (cannot be read: empty)
  test "the list this program carries (a short one in the tests) is readable":
    let rows = carriedPlaces()
    check rows.len >= 30
    check rows.len == parsePlaces(readFile("src/nimchoo/places/cities-test.tsv")).len
    var names: seq[string]
    for r in rows: names.add r.name
    check "Valparaíso" in names and "Zürich" in names

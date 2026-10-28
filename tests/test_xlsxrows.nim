import std/unittest
import nimchoo/xlsxrows

const profile = "../choochoo/data/sdk/Profile.xlsx"

suite "xlsxrows":
  test "Types sheet: known value":
    let rows = sheetRows(profile, "Types")
    check rows[0].cell(0) == "Type Name"
    var found = false
    for r in rows:
      if r.cell(2) == "farmers_walk":
        check r.cell(3) == "1"
        found = true
    check found

  test "absent cells are empty strings":
    let rows = sheetRows(profile, "Types")
    check rows[1].cell(99) == ""

import std/[strutils, unittest]
import nimchoo/packages/names/countryinfo as names

proc line(iso, name: string, id: int): string =
  ## A line of countryInfo.txt: 19 columns.
  var cols = newSeq[string](19)
  cols[0] = iso
  cols[4] = name
  cols[16] = $id
  cols.join("\t")

suite "names: the files about countries":
  test "the list of countries: code, name and id; comments and short lines are skipped":
    let text =
      "# comment\n#ISO\tISO3\n" & line("CL", "Chile", 3895114) & "\n" &
      line("PT", "Portugal", 2510769) & "\nshort\tline\n\n"
    let cs = names.parseCountryInfo(text)
    check cs.len == 2
    check cs[0] == names.CountryInfo(iso: "CL", name: "Chile", geonameId: 3895114)
    check cs[1].iso == "PT" and cs[1].geonameId == 2510769
    check names.parseCountryInfo("").len == 0

## Changing the names of climbs by hand.  A climb is found by the name `nch sector` shows for it, "(n/m)"
## and all.  A name given by a person is kept (`manual`) and the program never changes it; `--auto` hands the
## climb back, to be named again by the next `nch climbs`.

import std/[algorithm, strutils, tables]
import db_connector/db_sqlite
import ../climbs/[display, report]
import ../db/store
import ../errors
import ./params

{.push raises: [].}

func withoutNumber(shown: string): string =
  ## "Morro La Cabra (1/3)" -> "Morro La Cabra".
  if looksNumbered(shown): shown[0 ..< shown.rfind(" (")] else: shown

proc findShown*(st: Store, shown: string): int64 {.raises: [StoreError].} =
  ## The climb with that name as shown (without regard to case).  An error that says what to type if the
  ## name is shared and was given without its number, or if there is no such climb.
  let want = shown.strip.toLower
  let names = shownNames(st)
  var found: seq[int64]
  var sharing: seq[string]
  for id, text in names:
    if text.toLower == want: found.add id
    elif looksNumbered(text) and withoutNumber(text).toLower == want: sharing.add text
  if found.len == 1: return found[0]
  if found.len > 1: raiseStore("more than one climb is called '" & shown & "'")
  if sharing.len > 0:
    sharing.sort()
    raiseStore("'" & shown & "' is shared by " & $sharing.len & " climbs: say which one: " &
               sharing.join(", "))
  raiseStore("no climb is called '" & shown & "' (see `nch sector` for the names)")

proc shownName*(st: Store, id: int64): string {.raises: [StoreError].} =
  shownNames(st).getOrDefault(id, unnamed)

proc rename*(st: Store, id: int64, name: string) {.raises: [StoreError].} =
  ## Give the climb a name of the person's choosing: kept, and not looked at again by the program.
  guard:
    st.db.exec(sql"update sector set name = ?, manual = 1, name_checked = 1 where id = ?", name.strip, id)

proc setAuto*(st: Store, id: int64) {.raises: [StoreError].} =
  ## Forget the name: the next `nch climbs` makes one from the places near the climb.
  guard:
    st.db.exec(sql"update sector set name = null, manual = 0, name_checked = 0 where id = ?", id)

func catalogueLines*(rows: seq[SectorRow]): seq[string] =
  ## The climbs, one to a line, biggest gain first; "manual" marks the names given by a person.
  var cells = @[@["climb", "length", "gain", "gradient", "cat", "efforts", ""]]
  for s in rows:
    cells.add @[cut(s.name), km(s.lengthM) & " km", "+" & $int(s.gainM + 0.5) & " m",
                formatFloat(s.gradient, ffDecimal, 1) & " %", s.category, $s.efforts,
                (if s.manual: "manual" else: "")]
  columns(cells, {1, 2, 3, 5})

## Changing the names of climbs by hand.  A climb is found by the name `nch sector` shows for it, "(n/m)"
## and all.  A name given by a person is kept (`manual`) and the program never changes it; `--auto` hands the
## climb back, to be named again by the next `nch climbs`.

import std/[algorithm, strutils, tables]
import db_connector/db_sqlite
import ../climbs/[display, report]
import ../describe
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
    st.db.exec(sql"update sector set name = ?, manual = 1 where id = ?", name.strip, id)

proc setAuto*(st: Store, id: int64) {.raises: [StoreError].} =
  ## Forget the name (null): the command then names the climb again from the places near it (`ensureSectorNames`).
  guard:
    st.db.exec(sql"update sector set name = null, manual = 0 where id = ?", id)

proc setRetired*(st: Store, id: int64, retired: bool) {.raises: [StoreError].} =
  ## Hide the climb from the lists, or show it again.  Nothing else changes: it keeps its efforts, its place in the
  ## numbering of its name, and takes the efforts of new rides.
  guard:
    st.db.exec(sql"update sector set retired = ? where id = ?", (if retired: 1 else: 0), id)

func catalogueLines*(rows: seq[SectorRow]): seq[string] =
  ## The climbs, one to a line, biggest gain first, each the standard way; "manual" marks the names given by a person.
  var cells = @[@["climb", "cat", "length", "gain", "gradient", "efforts", ""]]
  for s in rows:
    cells.add climbCells(ClimbInfo(name: cut(s.name), category: s.category, lengthM: s.lengthM, gainM: s.gainM,
                                   gradient: s.gradient)) & @[$s.efforts, (if s.manual: "manual" else: "")]
  columns(cells, {2, 3, 4, 5})

## Changing the names of climbs by hand.  A climb is found by the name `nch climbs --all` shows for it, number
## (subscript) and all.  A name given by a person is kept (`manual`) and the program never changes it; `--auto` hands the
## climb back, to be named again by the next `nch climbs`.

import std/[algorithm, sequtils, strutils, tables]
import db_connector/db_sqlite
import ../db/store
import ../errors
import ./[display, ordinal, report]

{.push raises: [].}

proc findShown*(st: Store, shown: string): int64 {.raises: [StoreError].} =
  ## The climb with that name as shown (without regard to case); "Farellones₃", "Farellones 3" and "Farellones3" all
  ## mean the third climb called Farellones.  An error that says what to type if the name is shared and was given
  ## without its number, or if there is no such climb.
  let wants = ordinalForms(shown).mapIt(it.toLower)
  let names = shownNames(st)
  var found: seq[int64]
  var sharing: seq[string]
  for id, text in names:
    let t = text.toLower
    if t in wants:
      found.add id
    elif endsWithSubscript(text) and withoutSubscript(t) == wants[0]:
      sharing.add text
  if found.len == 1:
    return found[0]
  if found.len > 1:
    raiseStore("more than one climb is called '" & shown & "'")
  if sharing.len > 0:
    sharing.sort()
    raiseStore(
      "'" & shown & "' is shared by " & $sharing.len & " climbs: say which one: " &
        sharing.join(", ")
    )
  raiseStore(
    "no climb is called '" & shown & "' (see `nch climbs --all` for the names)"
  )

proc shownName*(st: Store, id: int64): string {.raises: [StoreError].} =
  shownNames(st).getOrDefault(id, unnamed)

proc rename*(st: Store, id: int64, name: string) {.raises: [StoreError].} =
  ## Give the climb a name of the person's choosing: kept, and not looked at again by the program.
  guard:
    st.db.exec(sql"update sector set name = ?, manual = 1 where id = ?", name.strip, id)
  assignNumber(st, id)

proc setAuto*(st: Store, id: int64) {.raises: [StoreError].} =
  ## Forget the name (null): the command then names the climb again from the places near it (`ensureSectorNames`).
  guard:
    st.db.exec(sql"update sector set name = null, manual = 0 where id = ?", id)
  assignNumber(st, id)

proc setRetired*(st: Store, id: int64, retired: bool) {.raises: [StoreError].} =
  ## Hide the climb from the lists, or show it again.  Nothing else changes: it keeps its efforts, its place in the
  ## numbering of its name, and takes the efforts of new rides.
  guard:
    st.db.exec(
      sql"update sector set retired = ? where id = ?", (if retired: 1 else: 0), id
    )

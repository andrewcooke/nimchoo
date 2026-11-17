## The namers (naming/namers.nim): the order they are asked in, the first name proposed winning, and naming after an import
## (naming/imported.nim) for every activity with no name, even when the import added nothing.

import std/[options, sequtils, unittest]
import ../support/shims
import nimchoo/core/[errors, extension, globals]
import nimchoo/packages/db/statement
import nimchoo/packages/user/session
import nimchoo/packages/importer/after
import nimchoo/packages/names/[countries, lookup]
import nimchoo/packages/naming/[imported, namers, rules]
import ../support/namesdata
from nimchoo/registry import extensions

proc says(name: string): Propose =
  ## (a namer that always proposes `name`, or nothing for "")
  if name == "a swim":
    return proc(
        n: Names, ride: Ride, gpsErrors: var int
    ): Option[string] {.nimcall, raises: [StoreError, DownloadError].} =
      some("a swim")
  return proc(
      n: Names, ride: Ride, gpsErrors: var int
  ): Option[string] {.nimcall, raises: [StoreError, DownloadError].} =
    none(string)

suite "naming: the namers":
  test "they are asked highest precedence first; in the program, landmarks first and places last":
    let order = inOrder(
      @[
        Namer(name: "low", precedence: 1),
        Namer(name: "high", precedence: 9),
        Namer(name: "middle", precedence: 5),
      ]
    )
    check order.mapIt(it.name) == @["high", "middle", "low"]
    let real = inOrder(extensions.get(namerPoint))
    check real[0].name == "landmarks" and real[^1].name == "places"

  test "the first name proposed wins; a namer that says nothing is passed over; a ride with no positions is still asked about":
    let (st, dir) = fresh("namers")
    defer:
      st.close()
    let n = newNames(st, dir, envOf(Net()), silent())
    let quiet = Namer(name: "quiet", precedence: 9, propose: says(""))
    let swim = Namer(name: "swim", precedence: 5, propose: says("a swim"))
    check nameOf(n, 1, newSeq[Part](), @[placeNamer, quiet, swim]).name == "a swim"
    check nameOf(n, 1, newSeq[Part](), @[placeNamer, quiet]).name == ""

suite "naming: after an import":
  test "every activity with no name is named, though the import added nothing; then there is nothing to do":
    let (st, dir) = fresh("after")
    defer:
      st.close()
    discard dir
    st.db.execute(
      "insert into file(user_id, name, sha256, imported_at) values (:userId, 'swim', 'swim', 0)",
      userId = st.userId,
    )
    st.db.execute(
      "insert into activity(file_id, session, start_t, end_t) values (1, 0, 1000, 2000)"
    ) # (no positions: it needs nothing from the network)
    let ctx = quietContext(Globals(offline: true, extensions: extensions))
    check nameActivities.run(st, @[], ctx).len == 0
    check st.db.scalar(int, "select count(*) from activity_name where activity_id = 1") ==
      1
    check nameActivities.run(st, @[], ctx).len == 0 # (nothing left)

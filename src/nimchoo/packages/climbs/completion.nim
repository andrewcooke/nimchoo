## Completing climbs by name: `nch activities --climbs TEXT...` takes a word at a time (it finds the climbs whose names
## hold the text), so it is offered the words of the names; `nch climbs --edit NAME` takes a whole name, as `--all` shows it,
## and is offered those.  The names are the shown ones ("Farellones₂", the kept number included), which `displayNames` makes
## in code, so they are filtered here and not in SQL (a climb with no name is shown as "unnamed", and offered so).  Case and accents do not matter, as in the option itself.

import std/[algorithm, strutils, tables]
import ../../core/[errors, globals]
import ../db/store
import ../text/fold/fold
import ./report

{.push raises: [].}

proc completeClimbNames*(
    g: Globals, typed: string
): seq[string] {.raises: [StoreError].} =
  ## The names of the climbs (as shown) that start with `typed`, in order.
  let st = openStore(g)
  defer:
    st.close()
  let want = foldText(typed)
  for _, name in shownNames(st):
    if name.len > 0 and foldText(name).startsWith(want):
      result.add name
  result = result.sortedByIt((foldText(it), it))

proc completeClimbWords*(
    g: Globals, typed: string
): seq[string] {.raises: [StoreError].} =
  ## The words of the names of climbs that start with `typed`, in order.
  let st = openStore(g)
  defer:
    st.close()
  let want = foldText(typed)
  for _, name in shownNames(st):
    for word in name.splitWhitespace:
      if foldText(word).startsWith(want):
        result.add word
  result = result.sortedByIt((foldText(it), it))

## Completing the name of a landmark (`nch landmarks --delete NAME`): the landmarks whose names start with what has been typed.

import ../../core/[errors, globals]
import ../db/[prefix, sqltext, statement, store]

{.push raises: [].}

proc completeLandmarks*(
    g: Globals, typed: string
): seq[string] {.raises: [StoreError].} =
  ## The names of the landmarks that start with `typed`, in order.
  let st = openStore(g)
  defer:
    st.close()
  st.db.query(
    string,
    sqlOf("select name from landmark where ") & foldedPrefix("name", typed) &
      " order by fold(name), name",
  )

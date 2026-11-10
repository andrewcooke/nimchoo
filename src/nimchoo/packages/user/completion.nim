## Completing the name of a user (`--user NAME`, `nch users --edit NAME`, `--delete NAME`): the users whose names start with
## what has been typed.  Read-only when the shell asks (`Globals.readOnly`).

import ../../core/[errors, globals]
import ../db/[prefix, sqltext, statement, store]

{.push raises: [].}

proc completeUsers*(g: Globals, typed: string): seq[string] {.raises: [StoreError].} =
  ## The names of the users that start with `typed`, in order.
  let st = openStore(g)
  defer:
    st.close()
  st.db.query(
    string,
    sqlOf("select name from user where ") & foldedPrefix("name", typed) &
      " order by fold(name), name",
  )

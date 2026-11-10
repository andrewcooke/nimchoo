## Completing the name of a model (`nch ff --model NAME`): the models whose names start with what has been typed.

import ../../core/[errors, globals]
import ../db/[prefix, sqltext, statement, store]

{.push raises: [].}

proc completeModels*(g: Globals, typed: string): seq[string] {.raises: [StoreError].} =
  ## The names of the models that start with `typed`, in order.
  let st = openStore(g)
  defer:
    st.close()
  st.db.query(
    string,
    sqlOf("select name from ff_model where ") & foldedPrefix("name", typed) &
      " order by fold(name), name",
  )

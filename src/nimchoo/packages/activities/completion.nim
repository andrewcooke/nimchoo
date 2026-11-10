## Completing the sports of `nch activities --sport` and `--sub-sport`: those the user's activities have, that start with
## what has been typed.  (`none`, which the options also take, and `latest` and `previous` are not offered: they are not
## sports.)

import std/strformat
import ../../core/[errors, globals]
import ../db/[prefix, sqltext, statement]
import ../user/session

{.push raises: [].}

type Column = enum
  ## the columns of `activity` that name a kind of activity
  cSport = "sport"
  cSubSport = "sub_sport"

proc valuesOf(
    g: Globals, column: Column, typed: string
): seq[string] {.raises: [StoreError].} =
  ## The distinct values of the column, over the activities of the user, that start with `typed`.
  let st = openSession(g)
  defer:
    st.close()
  let name = fmt"a.{column}"
  st.db.query(
    string,
    sqlFrom(
      fmt"select distinct {name} from activity a join file f on f.id = a.file_id where f.user_id = :user and {name} is not null and ",
      "activities",
    )
      .with("user", st.userId) & foldedPrefix(name, typed) &
      fmt" order by fold({name}), {name}",
  )

proc completeSports*(g: Globals, typed: string): seq[string] {.raises: [StoreError].} =
  ## The sports of the user's activities that start with `typed`.
  g.valuesOf(cSport, typed)

proc completeSubSports*(
    g: Globals, typed: string
): seq[string] {.raises: [StoreError].} =
  ## The sub-sports of the user's activities that start with `typed`.
  g.valuesOf(cSubSport, typed)

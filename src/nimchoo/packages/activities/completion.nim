## Completing the tags of `nch activities --tags`: those the user's activities have, that start with what has been typed
## (case and accents aside).  (A pattern with `*` is the user's to write: only whole tags are offered.)

import ../../core/[errors, globals]
import ../db/[prefix, sqltext, statement]
import ../user/session

{.push raises: [].}

proc completeTags*(g: Globals, typed: string): seq[string] {.raises: [StoreError].} =
  ## The tags of the user's activities that start with `typed`, in the order of their folded forms.
  let st = openSession(g)
  defer:
    st.close()
  st.db.query(
    string,
    sqlFrom(
      "select tag from (select distinct t.tag, t.folded from activity_tag t join activity a on a.id = t.activity_id " &
        "join file f on f.id = a.file_id where f.user_id = :user and ",
      "activities",
    )
      .with("user", st.userId) & foldedPrefix("t.tag", typed) & ") order by folded, tag",
  )

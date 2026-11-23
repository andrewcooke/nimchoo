## The selection: the activities that commands work on unless they are told otherwise, kept in the database for the user.

import ../db/statement
import ../db/store
import ../../core/errors
import ../user/session

{.push raises: [].}

proc replaceSelection*(st: Session, ids: seq[int64]) {.raises: [StoreError].} =
  ## Make the activities `ids` the selection of the store's user, in place of the one there was: all or nothing.
  ## (The caller says which: a query that joins other packages' tables is its own to run.)
  st.beginWrite()
  var done = false
  try:
    st.db.execute("delete from selection where user_id = :userId", userId = st.userId)
    st.db.execute(
      """insert into selection(user_id, activity_id)
          select :userId, value from json_each(:ids)""",
      userId = st.userId,
      ids = jsonList(ids),
    )
    st.commit()
    done = true
  finally:
    if not done:
      st.rollback()

proc addToSelection*(st: Session, ids: seq[int64]): int {.raises: [StoreError].} =
  ## Add the activities `ids` to the selection of the store's user (those already in it stay once); how many it holds now.
  st.writing(
    proc() {.closure, raises: [StoreError].} =
      st.db.execute(
        """insert or ignore into selection(user_id, activity_id)
            select :userId, value from json_each(:ids)""",
        userId = st.userId,
        ids = jsonList(ids),
      )
  )
  st.db.scalar(
    int, "select count(*) from selection where user_id = :userId", userId = st.userId
  )

proc selectedIds*(st: Session): seq[int64] {.raises: [StoreError].} =
  ## The ids of the current selection of the store's user, in order.
  st.db.query(
    int64,
    "select activity_id from selection where user_id = :userId order by 1",
    userId = st.userId,
  )

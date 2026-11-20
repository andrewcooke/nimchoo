## The climbs selection: the climbs a user has chosen (`climb_selection`), what `nch climbs` lists and the climbs subject's
## views show, as `selection` is the activities'.  Chosen by `nch climbs CRITERIA --select` and by an import.

import ../db/statement
import ../db/store
import ../../core/errors
import ../user/session

{.push raises: [].}

proc replaceClimbSelection*(st: Session, ids: seq[int64]) {.raises: [StoreError].} =
  ## Make the climbs `ids` the climbs selection of the store's user, in place of the one there was: all or nothing.
  st.beginWrite()
  var done = false
  try:
    st.db.execute(
      "delete from climb_selection where user_id = :userId", userId = st.userId
    )
    st.db.execute(
      """insert or ignore into climb_selection(user_id, sector_id)
          select :userId, value from json_each(:ids)""",
      userId = st.userId,
      ids = jsonList(ids),
    )
    st.commit()
    done = true
  finally:
    if not done:
      st.rollback()

proc chosenClimbs*(st: Session): seq[int64] {.raises: [StoreError].} =
  ## The climbs of the store's user's selection, the biggest first; a retired one is hidden, as it is from every list.
  st.db.query(
    int64,
    """select s.id from climb_selection c join sector s on s.id = c.sector_id
        where c.user_id = :userId and s.retired = 0 order by s.gain_m desc, s.id""",
    userId = st.userId,
  )

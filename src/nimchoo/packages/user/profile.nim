## The user's profile (`user_profile`, which this package owns): the threshold heart rate.

import ../db/[statement, store]
import ../../core/errors

{.push raises: [].}

proc setFthr*(st: Store, id: UserId, fthr: int) {.raises: [StoreError].} =
  st.db.execute(
    """insert into user_profile(user_id, fthr) values (:userId, :fthr)
      on conflict(user_id) do update set fthr = excluded.fthr""",
    userId = id,
    fthr = fthr,
  )

proc clearFthr*(st: Store, id: UserId) {.raises: [StoreError].} =
  st.db.execute(
    "update user_profile set fthr = null where user_id = :userId", userId = id
  )

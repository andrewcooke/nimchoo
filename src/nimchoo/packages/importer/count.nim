## What `nch users` says of the activities a user has: how many.  Contributed to `user/has` (see package.nim).

import ../../core/[errors, ids]
import ../db/statement
import ../user/has

{.push raises: [].}

proc activitiesOf(db: DbConn, user: UserId): int {.raises: [StoreError].} =
  db.scalar(
    int,
    """select count(*) from activity a join file f on f.id = a.file_id
      where f.user_id = :userId""",
    userId = user,
  )

let activityCount* =
  UserHas(heading: "activities", one: "activity", count: activitiesOf)
  ## the activities of a user

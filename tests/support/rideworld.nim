## A database with one ride with heart rate (`2018-08-27-rec.fit`), selected, and an FTHR (unless told otherwise), for the
## tests of what is worked out from the impulses (the views of `ff`).  Each world has its own cache (`NCH_CACHE`): a test
## that uses one ends with `useTestCache()`.

import std/os
import nimchoo/packages/db/statement
import nimchoo/packages/fit/load
import nimchoo/packages/heartrate/step
import nimchoo/packages/user/session
import nimchoo/packages/util/bytes/bytes
import nimchoo/packages/util/warnings/warnings
import ./shims
from nimchoo/registry import allFragments, allAccess

let dir = getTempDir() / "nch-test-rides"

proc world*(name: string, fthr = true): tuple[db, cache: string] =
  ## One ride with heart rate, selected, and (if `fthr`) an FTHR.
  removeDir(dir / name)
  createDir(dir / name)
  result = (dir / name / "x.db", dir / name / "cache" / "user")
  putEnv("NCH_CACHE", dir / name / "cache")
  let s = openSession(result.db, allFragments, access = allAccess)
  defer:
    s.close()
  var ws: seq[Warning]
  discard s.importFile(
    loadProfile("../choochoo/data/sdk/Profile.xlsx"),
    "r.fit",
    readBytes("../choochoo/data/test/source/personal/2018-08-27-rec.fit"),
    ws,
    @[heartrateStep],
  )
  s.db.execute(
    "insert into activity_selection(user_id, activity_id) select :userId, id from activity",
    userId = s.userId,
  )
  if fthr:
    s.db.execute(
      "insert into user_profile(user_id, fthr) values (:userId, 154)", userId = s.userId
    )

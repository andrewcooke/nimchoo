## Deleting the selected activities of the current user, with everything made from them (coordinates, route, breaks,
## channels, impulses, efforts, the record that the climbs were looked for): they all go with the activity through
## `on delete cascade`.  The climbs themselves (sectors) and the names on them stay: they are copies.  A file that has no
## activity left is forgotten too (its record and the paths it was seen at), so that importing the folder again brings its
## activities back; a file that still holds other activities (a file can hold several) stays, and so does its memory.

import std/algorithm
import ../db/statement
import ../db/store
import ../../core/errors
import ../user/session
import ../fit/time

{.push raises: [].}

type
  Plan* = object
    ids*: seq[ActivityId] ## the activities to delete (the current user's)
    fileOf*: seq[FileId] ## the file of each (parallel to `ids`)
    fileIds*: seq[FileId] ## their files (each once)
    first*, last*: UnixTime ## when the first and the last of them began

  Done* = object
    activities*: int
    files*: int ## files forgotten (no activity left)
    kept*: int ## files kept: they hold other activities

proc planDelete*(st: Session, ids: seq[int64]): Plan {.raises: [StoreError].} =
  ## What deleting these activities (of the current user) would take: their files and the dates.
  var files: seq[FileId]
  # id, file, start
  var rows = st.db.query(
    (ActivityId, FileId, int64),
    "select a.id, a.file_id, a.start_epoch from activity a " &
      "join file f on f.id = a.file_id where f.user_id = :userId and " &
      "a.id in (select value from json_each(:ids))",
    userId = st.userId,
    ids = jsonList(ids),
  )
  rows.sort(
    proc(a, b: (ActivityId, FileId, int64)): int =
      result = cmp(a[2], b[2])
      if result == 0:
        result = cmp(int64(a[0]), int64(b[0]))
  )
  for (id, file, t) in rows:
    result.ids.add id
    result.fileOf.add file
    if file notin files:
      files.add file
    if result.ids.len == 1:
      result.first = UnixTime(t)
    result.last = UnixTime(t)
  result.fileIds = files

const chunk* = 25
  ## activities deleted between two reports of progress (a ride with a track takes about 9 ms)

proc deleteActivities*(
    st: Store,
    p: Plan,
    progress: proc(done, total, files: int) {.closure, raises: [].} = nil,
): Done {.raises: [StoreError].} =
  ## Delete the activities of the plan, and each file when it is left with none (so the count of files forgotten grows
  ## with the activities).  One transaction: all or nothing.  `progress` is told, after each few activities, how many are
  ## gone and how many files are forgotten.
  st.beginWrite()
  var done = false
  try:
    var at = 0
    while at < p.ids.len:
      let stop = min(at + chunk, p.ids.len)
      st.db.execute(
        "delete from activity where id in (select value from json_each(:ids))",
        ids = jsonList(p.ids[at ..< stop]),
      )
      # the files of these activities that have none left (one that still has an activity in a later chunk is met again then)
      var files: seq[FileId]
      for k in at ..< stop:
        if p.fileOf[k] notin files:
          files.add p.fileOf[k]
      st.db.execute(
        "delete from file where id in (select value from json_each(:ids)) " &
          "and id not in (select file_id from activity)",
        ids = jsonList(files),
      )
      result.files +=
        files.len -
        st.db.scalar(
          int,
          "select count(*) from file where id in (select value from json_each(:ids))",
          ids = jsonList(files),
        )
      at = stop
      if progress != nil:
        progress(at, p.ids.len, result.files)
    result.activities = p.ids.len
    # the files that are still there are those with activities that were not selected
    var remaining = 0
    var k = 0
    while k < p.fileIds.len:
      let stop = min(k + 500, p.fileIds.len)
      remaining +=
        st.db.scalar(
          int,
          "select count(*) from file where id in (select value from json_each(:ids))",
          ids = jsonList(p.fileIds[k ..< stop]),
        )
      k = stop
    result.kept = remaining
    result.files = p.fileIds.len - remaining
    st.commit()
    done = true
  finally:
    if not done:
      st.rollback()

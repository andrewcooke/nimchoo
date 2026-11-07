## Deleting the selected activities of the current user, with everything made from them (coordinates, route, segments,
## heart rate, impulses, efforts, the record that the climbs were looked for): they all go with the activity through
## `on delete cascade`.  The climbs themselves (sectors) and the names on them stay: they are copies.  A file that has no
## activity left is forgotten too (its record and the paths it was seen at), so that importing the folder again brings its
## activities back; a file that still holds other activities (a file can hold several) stays, and so does its memory.

import std/[algorithm, strutils, tables, times]
import db_connector/db_sqlite
import ../db/store
import ../errors

{.push raises: [].}

type
  Plan* = object
    ids*: seq[int64] ## the activities to delete (the current user's)
    fileOf*: seq[int64] ## the file of each (parallel to `ids`)
    fileIds*: seq[int64] ## their files (each once)
    first*, last*: int64 ## when the first and the last of them began (Unix seconds)
    sports*: seq[(string, int)]
      ## how many of each sport ("" is not recorded), the most first

  Done* = object
    activities*: int
    files*: int ## files forgotten (no activity left)
    kept*: int ## files kept: they hold other activities

func list(ids: openArray[int64]): string =
  ## "1, 2, 3": numbers, so safe to put in a statement.
  for i, id in ids:
    if i > 0:
      result.add ", "
    result.add $id

proc planDelete*(st: Store, ids: seq[int64]): Plan {.raises: [StoreError].} =
  ## What deleting these activities (of the current user) would take: their files, the sports and the dates.
  var files: seq[int64]
  var sports = initTable[string, int]()
  var at = 0
  var rows: seq[(int64, int64, int64, string)] # id, file, start, sport
  while at < ids.len:
    let stop = min(at + 500, ids.len)
    guard:
      for r in st.db.fastRows(
        sql(
          "select a.id, a.file_id, a.start_t, coalesce(a.sport, '') from activity a " &
            "join file f on f.id = a.file_id where f.user_id = " & $st.userId &
            " and a.id in (" & list(ids[at ..< stop]) & ")"
        )
      ):
        try:
          rows.add (
            parseBiggestInt(r[0]), parseBiggestInt(r[1]), parseBiggestInt(r[2]), r[3]
          )
        except ValueError:
          raiseStore("a bad number in the activities")
    at = stop
  rows.sort(
    proc(a, b: (int64, int64, int64, string)): int =
      result = cmp(a[2], b[2])
      if result == 0:
        result = cmp(a[0], b[0])
  )
  for (id, file, t, sport) in rows:
    result.ids.add id
    result.fileOf.add file
    if file notin files:
      files.add file
    if result.ids.len == 1:
      result.first = t
    result.last = t
    sports.mgetOrPut(sport, 0) += 1
  result.fileIds = files
  for sport, n in sports:
    result.sports.add (sport, n)
  result.sports.sort(
    proc(a, b: (string, int)): int =
      result = cmp(b[1], a[1])
      if result == 0:
        result = cmp(a[0], b[0])
  )

proc describe*(p: Plan): string =
  ## "12 activities (cycling 9, running 3) from 2018-07-01 to 2026-10-30".
  let n = p.ids.len
  result = $n & (if n == 1: " activity" else: " activities")
  if n == 0:
    return
  var sp: seq[string]
  for (sport, k) in p.sports:
    sp.add (if sport.len > 0: sport else: "no sport") & " " & $k
  result.add " (" & sp.join(", ") & ")"
  let a = fromUnix(p.first).utc.format("yyyy-MM-dd")
  let b = fromUnix(p.last).utc.format("yyyy-MM-dd")
  result.add (if a == b: " on " & a else: " from " & a & " to " & b)

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
  st.begin()
  var done = false
  try:
    var at = 0
    while at < p.ids.len:
      let stop = min(at + chunk, p.ids.len)
      guard:
        st.db.exec(
          sql("delete from activity where id in (" & list(p.ids[at ..< stop]) & ")")
        )
      # the files of these activities that have none left (one that still has an activity in a later chunk is met again then)
      var files: seq[int64]
      for k in at ..< stop:
        if p.fileOf[k] notin files:
          files.add p.fileOf[k]
      guard:
        st.db.exec(
          sql(
            "delete from file where id in (" & list(files) &
              ") and id not in (select file_id from activity)"
          )
        )
        try:
          result.files +=
            files.len -
            parseInt(
              st.db.getValue(
                sql("select count(*) from file where id in (" & list(files) & ")")
              )
            )
        except ValueError:
          raiseStore("a bad count")
      at = stop
      if progress != nil:
        progress(at, p.ids.len, result.files)
    result.activities = p.ids.len
    # the files that are still there are those with activities that were not selected
    var remaining = 0
    var k = 0
    while k < p.fileIds.len:
      let stop = min(k + 500, p.fileIds.len)
      guard:
        try:
          remaining +=
            parseInt(
              st.db.getValue(
                sql(
                  "select count(*) from file where id in (" & list(
                    p.fileIds[k ..< stop]
                  ) & ")"
                )
              )
            )
        except ValueError:
          raiseStore("a bad count")
      k = stop
    result.kept = remaining
    result.files = p.fileIds.len - remaining
    st.commit()
    done = true
  finally:
    if not done:
      st.rollback()

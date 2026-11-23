## The tags a scope of `nch tags` means (`params.nim`), counted, added, removed and renamed: each one statement in SQL over
## the tags of the user's activities.

import std/[options, strformat]
import ../../core/errors
import ../db/[sqltext, statement, store]
import ../user/session
import ./[params, tag]

{.push raises: [].}

func patternsSql(patterns: seq[TagPattern]): Sql =
  ## " and (t.folded glob :p0 or ...)": the tag matches any of the patterns.
  var parts: seq[Sql]
  for k, p in patterns:
    let name = fmt"namePattern{k}"
    parts.add sqlOf("t.folded glob :" & name).with(name, foldedPattern(p))
  result = sqlOf(" and (") & parts[0]
  for p in parts[1 .. ^1]:
    result = result & " or " & p
  result = result & ")"

proc rowsSql(st: Session, scope: TagScope): Sql =
  ## " from ... where ...": the tags (`t`) of the user's activities (`a`) that the scope means.
  result = sqlOf(
      " from activity_tag t join activity a on a.id = t.activity_id join file f on f.id = a.file_id where f.user_id = :owner"
    )
    .with("owner", st.userId)
  let selected =
    " and t.activity_id in (select activity_id from activity_selection where user_id = :owner)"
  case scope.kind
  of tsSelection:
    result = result & selected
  of tsAll:
    discard
  of tsMatching:
    if scope.within:
      result = result & selected
    result = result & patternsSql(scope.patterns)

proc counts*(
    st: Session, scope: TagScope
): seq[tuple[tag: string, n: int]] {.raises: [StoreError].} =
  ## Each tag the scope means (as it was first given), and how many activities have it, in the order of the folded forms.
  st.db.query(
    tuple[tag: string, n: int],
    sqlOf("select min(t.tag), count(*)") & st.rowsSql(scope) &
      " group by t.folded order by t.folded",
  )

proc activitiesSql(st: Session, scope: TagScope): Sql =
  ## The activities the scope means: the selected ones, all of the user's, or those that have a tag it finds.
  case scope.kind
  of tsSelection:
    sqlOf("select activity_id from activity_selection where user_id = :owner").with(
      "owner", st.userId
    )
  of tsAll:
    sqlOf(
      "select a.id from activity a join file f on f.id = a.file_id where f.user_id = :owner"
    )
      .with("owner", st.userId)
  of tsMatching:
    sqlOf("select distinct t.activity_id") & st.rowsSql(scope)

proc activityCount*(st: Session, scope: TagScope): int {.raises: [StoreError].} =
  ## How many activities the scope means.
  st.db.scalar(int, sqlOf("select count(*) from (") & st.activitiesSql(scope) & ")")

proc addTo*(
    st: Session, scope: TagScope, tags: seq[Tag]
): tuple[activities, added: int] {.raises: [StoreError].} =
  ## Give the activities of the scope these tags (one that has a tag already keeps it as it was): how many activities, and how
  ## many tags were new, all in one transaction.
  let ids = st.db.query(int64, st.activitiesSql(scope))
  result.activities = ids.len
  var added = 0
  st.writing(
    proc() {.closure, raises: [StoreError].} =
      for t in tags:
        st.db.execute(
          "insert or ignore into activity_tag(activity_id, tag, folded) select value, :tag, :folded from json_each(:ids)",
          tag = $t,
          folded = t.folded,
          ids = jsonList(ids),
        )
        added += st.db.scalar(int, "select changes()")
  )
  result.added = added

proc remove*(st: Session, scope: TagScope): int {.raises: [StoreError].} =
  ## Remove the tags the scope means from their activities; how many were removed.
  st.writing(
    proc() {.closure, raises: [StoreError].} =
      st.db.execute(
        sqlOf(
          "delete from activity_tag where (activity_id, folded) in (select t.activity_id, t.folded"
        ) & st.rowsSql(scope) & ")"
      )
  )
  st.db.scalar(int, "select changes()")

proc merges*(st: Session, scope: TagScope, new: Tag): int {.raises: [StoreError].} =
  ## How many of the activities with the tag the scope finds have `new` already (renaming would make the two one).
  st.db.scalar(
    int,
    sqlOf("select count(*)") & st.rowsSql(scope) &
      sqlOf(
        " and exists (select 1 from activity_tag n where n.activity_id = t.activity_id and n.folded = :newFolded)"
      )
      .with("newFolded", new.folded),
  )

proc rename*(st: Session, scope: TagScope, new: Tag): int {.raises: [StoreError].} =
  ## Give the tags the scope finds (one tag) the name `new`; where an activity has `new` already the old one goes.  How many
  ## activities have `new` now from them.
  let ids = st.db.query(int64, sqlOf("select t.activity_id") & st.rowsSql(scope))
  let old = st.db.query(string, sqlOf("select distinct t.folded") & st.rowsSql(scope))
  st.writing(
    proc() {.closure, raises: [StoreError].} =
      for f in old:
        if f != new.folded: # (a new case or accent only: the same tag, written again)
          st.db.execute(
            """delete from activity_tag where folded = :old and activity_id in (select value from json_each(:ids))
             and activity_id in (select activity_id from activity_tag where folded = :newFolded)""",
            old = f,
            ids = jsonList(ids),
            newFolded = new.folded,
          )
        st.db.execute(
          """update activity_tag set tag = :tag, folded = :newFolded
             where folded = :old and activity_id in (select value from json_each(:ids))""",
          tag = $new,
          newFolded = new.folded,
          old = f,
          ids = jsonList(ids),
        )
  )
  ids.len

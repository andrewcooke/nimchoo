## What a tag and a pattern of tags are, how they are matched, and how they are kept: the one place tags are read from
## text and written to the database.  `Tag` and `TagPattern` can only hold what is allowed.

import std/[options, strformat, unicode]
import ../../core/[errors, ids]
import ../db/[sqltext, statement, store]
import ../text/fold/fold

{.push raises: [].}

type
  Tag* = distinct string
    ## letters (accents too), digits, `-`, `_` and `:`; not starting with `-`
  TagPattern* = distinct string ## as a tag, and `*` for anything

func `$`*(t: Tag): string {.borrow.}
func `==`*(a, b: Tag): bool {.borrow.}
func `$`*(p: TagPattern): string {.borrow.}
func `==`*(a, b: TagPattern): bool {.borrow.}

func problemOf(text: string, star: bool): Option[string] =
  ## What is wrong with `text` as a tag (or, with `star`, a pattern); none if nothing is.
  let what = if star: "a pattern of tags" else: "a tag"
  if text.len == 0:
    return some(fmt"{what} is not empty")
  if text[0] == '-':
    return
      some(fmt"{what} does not start with '-' (it would read as an option): '{text}'")
  for r in text.runes:
    let fine =
      r.isAlpha or (r.int32 >= ord('0') and r.int32 <= ord('9')) or
      r.int32 in [ord('-'), ord('_'), ord(':')] or (star and r.int32 == ord('*'))
    if not fine:
      let allowed =
        if star:
          "letters, digits, '-', '_', ':' and '*'"
        else:
          "letters, digits, '-', '_' and ':'"
      return some(fmt"{what} holds only {allowed}: '{text}' has '{r}'")
  none(string)

func parseTag*(text: string): tuple[tag: Option[Tag], problem: Option[string]] =
  ## `text` as a tag, or what is wrong with it.
  let p = problemOf(text, false)
  if p.isSome:
    (none(Tag), p)
  else:
    (some(Tag(text)), none(string))

func parsePattern*(
    text: string
): tuple[pattern: Option[TagPattern], problem: Option[string]] =
  ## `text` as a pattern of tags (`*` for anything), or what is wrong with it.
  let p = problemOf(text, true)
  if p.isSome:
    (none(TagPattern), p)
  else:
    (some(TagPattern(text)), none(string))

func folded*(t: Tag): string =
  ## What a tag is matched as: lower case, no accents.
  foldText($t)

func tagsSql*(patterns: openArray[TagPattern], activity = "a.id"): Sql =
  ## Conditions, each " and exists (...)", that the activity `activity` (a column of the query) has a tag matching every
  ## pattern.  A pattern is folded as the tags are, and `*` is GLOB's: a tag holds none of GLOB's other marks.
  for k, p in patterns:
    let name = fmt"tagPattern{k}"
    result =
      result &
      sqlOf(
        " and exists (select 1 from activity_tag t where t.activity_id = " & activity &
          " and t.folded glob :" & name & ")"
      )
      .with(name, foldText($p))

proc addTags*(
    db: DbConn, activity: ActivityId, tags: openArray[Tag]
): int {.raises: [StoreError].} =
  ## Give the activity these tags (one it has already, whatever its case or accents, stays as it was); how many were new.
  ## (On a connection: an import step writes inside the importer's transaction.)
  for t in tags:
    db.execute(
      "insert or ignore into activity_tag(activity_id, tag, folded) values (:activity, :tag, :folded)",
      activity = activity,
      tag = $t,
      folded = t.folded,
    )
    result += db.scalar(int, "select changes()")

proc addTags*(
    st: Store, activity: ActivityId, tags: openArray[Tag]
) {.raises: [StoreError].} =
  ## Give the activity these tags (one it has already, whatever its case or accents, stays as it was).
  discard st.db.addTags(activity, tags)

proc removeTags*(
    st: Store, activity: ActivityId, tags: openArray[Tag]
) {.raises: [StoreError].} =
  ## Take these tags from the activity (whatever their case or accents); one it does not have is no matter.
  for t in tags:
    st.db.execute(
      "delete from activity_tag where activity_id = :activity and folded = :folded",
      activity = activity,
      folded = t.folded,
    )

proc tagsOf*(st: Store, activity: ActivityId): seq[Tag] {.raises: [StoreError].} =
  ## The tags of the activity, as they were given, in order.
  for t in st.db.query(
    string,
    "select tag from activity_tag where activity_id = :activity order by folded",
    activity = activity,
  ):
    result.add Tag(t)

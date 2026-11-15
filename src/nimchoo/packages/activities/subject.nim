## The activities as a subject (`subject/subjects`): what the views show by default, with the user's selection of them.
## The key of the selection is made from the user and the ids selected, in order; what the activities hold is keyed by the
## counters of their tables.

import std/strutils
import ../../core/[errors, extension]
import ../selection/selection
import ../subject/[keys, subjects]
import ../user/session

{.push raises: [].}

proc selectionKey(st: Session): string {.raises: [StoreError].} =
  ## The same while the user's selection holds the same activities.
  var ids: seq[string]
  for id in selectedIds(st):
    ids.add $id
  keyOf([("user", $int64(st.userId)), ("ids", ids.join(","))])

const activitiesSubject* = Subject(
  name: "activities",
  summary: "the activities of the selection (see `nch activities --select`)",
  isDefault: true,
  selectionKey: selectionKey,
)

proc contribution*(): Contribution =
  ## The activities, offered to the subjects.
  contribute(subjectPoint, activitiesSubject)

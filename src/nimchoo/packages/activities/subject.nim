## The activities as a subject (`subject/subjects`): what the views show by default, with the user's selection of them.

import ../../core/markup
import ../../core/[errors, extension]
import ../selection/selection
import ../subject/subjects
import ../user/session

{.push raises: [].}

proc selected(st: Session): int {.raises: [StoreError].} =
  selectedIds(st).len

const activitiesSubject* = Subject(
  name: "activities",
  summary: ~"the activities of the selection (see `nch activities --select`)",
  isDefault: true,
  selected: selected,
  emptyHint: ~"see `nch activities --select`",
)

proc contribution*(): Contribution =
  ## The activities, offered to the subjects.
  contribute(subjectPoint, activitiesSubject)

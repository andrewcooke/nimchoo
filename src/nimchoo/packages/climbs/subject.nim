## The climbs as a subject (`subject/subjects`): the user's climbs selection, which the views show with `nch map climbs` and
## `nch calendar climbs`.

import ../ui/markup
import ../../core/[errors, extension]
import ../subject/subjects
import ../user/session
import ./chosen

{.push raises: [].}

proc selected(st: Session): int {.raises: [StoreError].} =
  chosenClimbs(st).len

const climbsSubject* = Subject(
  name: "climbs",
  summary: ~"the climbs of the climbs selection (see `nch climbs --select`)",
  isDefault: false,
  selected: selected,
  emptyHint: ~"see `nch climbs CRITERIA --select`",
)

proc contribution*(): Contribution =
  ## The climbs, offered to the subjects.
  contribute(subjectPoint, climbsSubject)

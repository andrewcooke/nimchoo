## The models as a subject (`subject/subjects`), called `ff` in the views: the user's models selection, whose fitness,
## fatigue and form `nch plot ff` draws.

import ../ui/markup
import ../../core/[errors, extension]
import ../subject/subjects
import ../user/session
import ./models

{.push raises: [].}

proc selected(st: Session): int {.raises: [StoreError].} =
  selectedModels(st.db, st.userId).len

const modelsSubject* = Subject(
  name: "ff",
  summary:
    ~"the fitness, fatigue and form of the models selection (see `nch models --select`)",
  isDefault: false,
  selected: selected,
  emptyHint: ~"see `nch models CRITERIA --select`",
)

proc contribution*(): Contribution =
  ## The models, offered to the subjects.
  contribute(subjectPoint, modelsSubject)

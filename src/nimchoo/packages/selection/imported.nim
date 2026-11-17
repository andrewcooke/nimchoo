## The new activities become the selection: what `selection` does once an import has finished (the point
## `importer/after`), so that the commands that work on the selection are ready to use on the ride just imported.

import std/strformat
import ../../core/errors
import ../importer/after
import ../ui/[style, vocabulary]
import ../user/session
import ./selection

{.push raises: [].}

proc selectImported(
    st: Session, ids: seq[int64], ctx: AfterContext
): seq[ImportReport] {.raises: [StoreError].} =
  st.replaceSelection(ids)
  let what =
    if ids.len == 1:
      "the new activity"
    else:
      fmt"the {ids.len} new activities"
  @[ImportReport(text: fmt"selected {what}", look: Look(colour: selectedColour))]

let selectNewActivities* =
  AfterImport(run: selectImported, failed: "the new activities could not be selected")
  ## after an import: the activities it made are the selection

## What other packages do once an import has finished: an extension point of this package.  `selection` makes the new
## activities the selection.  The importer calls each contribution once per import, after the files are committed and
## the activities named, with the activities that are new (this user's, in the order of their ids), and says what it
## reports.  One that fails does not undo the import: a warning says what was not done.

import std/options
import ../../core/[errors, extension]
import ../ui/style
import ../user/session

{.push raises: [].}

type
  ImportReport* = object
    ## What a contribution says it did: a line for the screen and the log, with the look of what it is about (the
    ## selection has its own: `ui/vocabulary.selectedColour`).
    text*: string
    look*: Look

  AfterImport* = object
    run*: proc(st: Session, ids: seq[int64]): Option[ImportReport] {.
      nimcall, raises: [StoreError]
    .} ## do it; `none`: nothing to say
    failed*: string ## said when it raised: "the new activities could not be selected"

const afterImport* = ExtensionPoint[AfterImport](name: "importer/after")
  ## What is done after an import (PACKAGES.md, "Extension points").

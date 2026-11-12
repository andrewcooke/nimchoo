## What other packages do once an import has finished: an extension point of this package.  `selection` makes the new
## activities the selection.  The importer calls each contribution once per import, after the files are committed and
## the activities named, with the activities that are new (this user's, in the order of their ids) and a context (the
## settings of the run, and how to be seen), and says what it reports, a line each.  One that fails does not undo the import:
## a warning says what was not done.

import ../../core/[errors, extension, globals]
import ../ui/style
import ../user/session

{.push raises: [].}

type
  ImportReport* = object
    ## What a contribution says it did: a line for the screen and the log, with the look of what it is about (the
    ## selection has its own: `ui/vocabulary.selectedColour`).
    text*: string
    look*: Look

  Show* = proc(lines: seq[Line], final: bool) {.closure, raises: [].}
    ## How a contribution shows work that takes a while: the lines that follow it, as often as it likes (the importer decides how
    ## often they are drawn, and whether at all: only on a terminal); `final` is the last frame, which stays on the screen.
    ## Library code does not print, so this is how the import's two live lines are drawn for it.

  Say* = proc(line: string) {.closure, raises: [].}
    ## A line for the screen (the downloads a step makes say theirs through it).

  AfterContext* = object
    ## What the importer gives a contribution besides the database: the settings of the run (the cache, `--offline`, the
    ## log), and the two ways to be seen.
    g*: Globals
    show*: Show
    say*: Say

  AfterImport* = object
    run*: proc(st: Session, ids: seq[int64], ctx: AfterContext): seq[ImportReport] {.
      nimcall, raises: [StoreError, DownloadError]
    .}
      ## do it, showing how far it has got; what it has to say, a line each (none: nothing)
    failed*: string ## said when it raised: "the new activities could not be selected"

proc noShow*(lines: seq[Line], final: bool) {.raises: [].} =
  ## A `Show` that shows nothing (for a contribution that is run where there is no display, as in a test).
  discard

proc noSay*(line: string) {.raises: [].} =
  ## A `Say` that says nothing.
  discard

func quietContext*(g: Globals): AfterContext =
  ## A context with no display, for a contribution that is run where there is none (a test): the settings are `g`'s.
  AfterContext(g: g, show: noShow, say: noSay)

const afterImport* = ExtensionPoint[AfterImport](name: "importer/after")
  ## What is done after an import (dev/PACKAGES.md, "Extension points").

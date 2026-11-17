## What a view is a view of: the type of a subject and the extension point they are contributed to.
##
## A subject is a kind of thing the user chooses and then looks at in different views (activities, later climbs and FF
## statistics).  The package that manages one contributes it; every view reads the registry of them, so that none has to know
## the packages above it.  Exactly one subject is the default (the one a view shows when it is not told: activities).

import ../../core/[errors, extension]
import ../user/session

{.push raises: [].}

type
  SelectedCount* = proc(st: Session): int {.nimcall, raises: [StoreError].}
    ## How many things the user's selection of the subject holds.

  Subject* = object
    name*: string ## what the user types: `nch map activities`
    summary*: string ## one line, for the list of subjects
    isDefault*: bool ## the subject a view shows when it is not told
    selected*: SelectedCount ## a view says "the selection is empty" when this is 0
    emptyHint*: string ## what to do about it: "see `nch activities --select`"

const subjectPoint* = ExtensionPoint[Subject](name: "subject/subjects")
  ## The subjects: contributed by the package that manages the selection of each.

proc defaultSubject*(all: seq[Subject]): Subject =
  ## The subject marked as the default.  A registry with none or with two is a bug (the tests check the real one).
  var found: seq[Subject]
  for s in all:
    if s.isDefault:
      found.add s
  doAssert found.len == 1, "there must be exactly one default subject"
  found[0]

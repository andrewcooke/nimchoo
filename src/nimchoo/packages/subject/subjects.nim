## What a view is a view of: the type of a subject and the extension point they are contributed to.
##
## A subject is a kind of thing the user chooses and then looks at in different views (activities, later climbs and FF
## statistics).  The package that manages one contributes it; every view reads the registry of them, so that none has to know
## the packages above it.  Exactly one subject is the default (the one a view shows when it is not told: activities).

import std/[options, sequtils, strutils]
import ../../core/[errors, extension, line]
import ../ui/markup
import ../util/args/args
import ../user/session

{.push raises: [].}

type
  SelectedCount* = proc(st: Session): int {.nimcall, raises: [StoreError].}
    ## How many things the user's selection of the subject holds.

  Subject* = object
    name*: string ## what the user types: `nch map activities`
    summary*: Line ## one line, for the list of subjects
    isDefault*: bool ## the subject a view shows when it is not told
    selected*: SelectedCount ## a view says "the selection is empty" when this is 0
    emptyHint*: Line ## what to do about it: "see `nch activities --select`"

func emptyText*(s: Subject): Line =
  ## What a view says, as a warning, when the selection it would show is empty: nothing to show is no failure.
  ~"the selection of {s.name} is empty (" & s.emptyHint & ~")"

const subjectPoint* = ExtensionPoint[Subject](name: "subject/subjects")
  ## The subjects: contributed by the package that manages the selection of each.

func isWord*(value: string): bool =
  ## A name of a subject or of a frame: lower case letters and digits.
  value.len > 0 and value.allIt(it in {'a' .. 'z', '0' .. '9'})

func takeSubject*(subjects: var seq[string], arg: string): Problem =
  ## The positional `SUBJECT` of a view: a name (`isWord`); `tooMany` is for the views to check when all is read.
  if not isWord(arg):
    return refuse(~"'{arg}' is not a name of a subject")
  subjects.add arg
  fine

const tooManySubjects* = ~"expected at most one SUBJECT"

proc defaultSubject*(all: seq[Subject]): Subject =
  ## The subject marked as the default.  A registry with none or with two is a bug (the tests check the real one).
  var found: seq[Subject]
  for s in all:
    if s.isDefault:
      found.add s
  doAssert found.len == 1, "there must be exactly one default subject"
  found[0]

func findSubject*(all: seq[Subject], asked: Option[string]): Option[Subject] =
  ## The subject the user named, or the default one when none was named; none if there is no such subject.
  let name =
    if asked.isSome:
      asked.get
    else:
      defaultSubject(all).name
  for s in all:
    if s.name == name:
      return some(s)

func noSubject*(all: seq[Subject], asked: Option[string], view: string): Line =
  ## Why `findSubject` found none: there are none that `view` ("a map") can show, or the name is not one of them.
  if all.len == 0:
    return ~"no subject can be shown on {view}"
  let names = all.mapIt(it.name).join(", ")
  ~"no subject '{asked.get}' (the subjects are {names})"

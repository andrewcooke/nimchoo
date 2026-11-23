## Editable objects: one shared piece for the named things made by hand (models; landmarks, users).
##
## The design is in `dev/editable-objects.md`.  A type declares itself once, as a `Kind`: its attributes (each with its
## option, how its value is read and shown, and its column), how its name is read and changed, and the rules beyond each
## attribute (`check`).  From that this package makes the options of the type's command (`--names PATTERN...` to list,
## `--add NAME [--base NAME]`, `--edit NAME [--rename NEW]`, `--delete`, then the attributes, whose values are given with
## `--add` and `--edit`), the parse of what is asked (`Action`), applying the values given (`made`, `edited`) and the
## table.  What is stored, and how, stays with the type's package (a table is written by its owner).  A type that is also
## a subject adds the steps of its selection (`subject/steps`) to the same parse: the selection is not this package's.

import ../../core/manifest

const package* = Package(depends: @["args", "subject", "ui"])

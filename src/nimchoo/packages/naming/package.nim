## Naming activities: where each started and what it is called, from the namers, after every import.
##
## A ride's name is the first that the **namers** propose, asked in order of precedence (dev/NAMING.md): the point
## `naming/namers` (`namers.nim`), to which this package contributes two and the packages above it more: **landmarks**
## (the author's own places, first), the ride's **big climb** (`climbs`), then the **places** near the route (GeoNames).  A
## namer words the whole name; the shapes of a ride and their wording ("X and back", "to X", "loop via X", "around X",
## "at X") and the start place are in `rules.nim`, for any namer that wants them.  The names are kept as text in
## `activity_name` (this package owns it), made once after each import (`importer/after`, `imported.nim`) for every activity
## that has none; a change of the rules is applied by rebuilding the database.  `names` is the library of places and
## landmarks underneath.

import ../../core/[extension, manifest]
import ../importer/after
import ./[imported, namers, rules]

proc contributions(): seq[Contribution] {.nimcall, raises: [].} =
  @[
    contribute(afterImport, nameActivities),
    contribute(namerPoint, landmarkNamer),
    contribute(namerPoint, placeNamer),
  ]

const package* = Package(
  depends: @["db", "download", "geo", "importer", "names", "profiling", "user"],
  fragments: @[
    fragment("001-schema.sql") # activity_name
  ],
  defines: @[
    PointDecl(
      name: namerPoint.name,
      summary:
        "what can name an activity: a namer with a precedence, which proposes a whole name or nothing; the first name proposed wins",
    )
  ],
  contributes: contributions,
)

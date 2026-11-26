## Subjects: what the views are views of (the activities, the climbs).
##
## Also the steps of a search that involve a subject's selection (`steps.nim`): the options `--all`, `--select`, `--also` and
## `--within`, the rules between them and the lines of the usage that say them, written once for every subject's command;
## and what every view does with the subjects and their frames (`views.nim`: choosing them, the usage's table, the stop
## when the selection is empty).

import ../../core/[extension, manifest]
import ./subjects

const package* = Package(
  depends: @["args", "user"],
  defines: @[
    PointDecl(
      name: subjectPoint.name,
      summary:
        "the subjects a view can show (activities, ...): a name, a summary, whether it is the default, and how many its selection holds",
    )
  ],
)

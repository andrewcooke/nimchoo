## Subjects: what the views are views of (the activities, the climbs).

import ../../core/[extension, manifest]
import ./subjects

const package* = Package(
  depends: @["args", "ui", "user"],
  defines: @[
    PointDecl(
      name: subjectPoint.name,
      summary:
        "the subjects a view can show (activities, ...): a name, a summary, whether it is the default, and how many its selection holds",
    )
  ],
)

## Subjects: what the views are views of, and the keys that say whether a frame is still current.

import ../../core/[extension, manifest]
import ./subjects

const package* = Package(
  depends: @["db", "hashing", "user", "version"],
  defines: @[
    PointDecl(
      name: subjectPoint.name,
      summary:
        "the subjects a view can show (activities, ...): a name, a summary, whether it is the default, and the key of its selection",
    )
  ],
)

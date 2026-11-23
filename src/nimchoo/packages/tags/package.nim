## Tags: small labels on activities ("bike:cotic", "sport:cycling:road"), to choose them by.
##
## The design and what was decided are in `dev/tags.md`.  This package holds the table and what a tag is:
##
## * **A tag** (`Tag`) is letters (accents too), digits, `-`, `_` and `:`, and does not start with `-` (it would read as an
##   option).  `key:value` is a convention only: nothing here reads it.  A **pattern** (`TagPattern`) may also hold `*`,
##   which matches anything (`bike:*`).
## * **Matching** ignores case and accents, as `--names` does: each tag is kept with its folded form (`fold`), and a
##   pattern is compared with that.  Two tags that fold the same are one tag on an activity (the first written is kept).
##   Several patterns are "and": an activity has a tag matching each (`tagsSql`).
## * **The table** `activity_tag` belongs to this package; tags go when their activity does.
##
## Who gives an activity its tags (the import, by hand) and who chooses activities by them (`activities --tags`) come later:
## `dev/tags.md`, TODO.

import ../../core/manifest

const package* = Package(
  depends: @["db", "fold", "importer"],
  fragments: @[
    fragment("001-schema.sql") # activity_tag: the tags of the activities
  ],
)

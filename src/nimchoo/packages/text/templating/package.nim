## Page templates: text with `{{tags}}` filled in from values.
##
## A subset of Mustache, enough for the pages and small enough to read in one sitting.  A comment must not contain a tag (the
## engine ends a comment at the first closing braces).

import ../../../core/manifest

const package* = Package(depends: @[], fragments: @[])

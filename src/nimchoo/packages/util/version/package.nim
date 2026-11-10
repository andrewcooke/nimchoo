## What `nch --version` says: the version in nimchoo.nimble and the git commit it was built from.
##
## Both are found when the program is compiled.

import ../../../core/manifest

const package* = Package(depends: @[], fragments: @[])

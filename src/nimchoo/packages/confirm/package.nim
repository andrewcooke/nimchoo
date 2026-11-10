## Deleting with a pause: the countdown that gives time to press Ctrl-C.
##
## Nothing is deleted without `--force`, and on a terminal there are then a few seconds to cancel (`activities --delete`,
## `users --delete`, `db --delete`, `climbs --all --delete`).  The line that says what was deleted is here too.

import ../../core/manifest

const package* = Package(depends: @["ui"], fragments: @[])

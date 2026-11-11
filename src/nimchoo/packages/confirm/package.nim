## Deleting with a pause: the countdown that gives time to press Ctrl-C.
##
## Nothing is deleted without `--force`, and on a terminal there are then a few seconds to cancel (`activities --delete`,
## `users --delete`, `db --delete`, `climbs --all --delete`); given twice (`-f -f`) there is no pause.  The option is written
## once here (`forceOption`, with the `Force` it sets: no, yes, now), so that every command that deletes has the same, and so is
## the pause (`pause`).  The line that says what was deleted is here too.

import ../../core/manifest

const package* = Package(depends: @["args", "ui"], fragments: @[])

## What a user has, as `nch users` says it: an extension point of this package, to which the packages whose data hangs off
## a user contribute a count (`importer`: the activities).  `nch users` shows each as a column, and says them when it asks
## before deleting a user ("74 activities and user bob"), so it needs to know none of those packages.

import ../../core/[errors, extension, ids]
import ../db/statement

{.push raises: [].}

type UserHas* = object
  heading*: string ## the column heading, and the plural: "activities"
  one*: string ## the singular: "activity"
  count*: proc(db: DbConn, user: UserId): int {.nimcall, raises: [StoreError].}
    ## how many the user has

const userHas* = ExtensionPoint[UserHas](name: "user/has")
  ## What a package offers to say of a user: a count with its name.

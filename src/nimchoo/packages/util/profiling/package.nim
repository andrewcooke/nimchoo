## Timers for finding out where a long job spends its time.
##
## Off unless the environment has `NCH_PROFILE`; then each `timed("phase")` adds its time to a table printed at the end.  It
## holds the program's only module-level mutable state, apart from the stop flag of the database's checkpointer.

import ../../../core/manifest

const package* = Package(depends: @[], fragments: @[])

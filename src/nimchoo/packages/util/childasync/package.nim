## Running a child process from an event loop, so that other requests are served meanwhile.
##
## The same steps as `child`, with `sleepAsync` between looks at the child's pipes.  It is a package of its own because async
## code is not `raises: []`.

import ../../../core/manifest

const package* = Package(depends: @["child"], fragments: @[])

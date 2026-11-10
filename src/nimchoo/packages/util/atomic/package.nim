## Writing a file so that nobody ever sees half of it.
##
## The one way the program writes a file that others read: the text goes to a file of its own, which is then renamed over the
## target.

import ../../../core/manifest

const package* = Package(depends: @[], fragments: @[])

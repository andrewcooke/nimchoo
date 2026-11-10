## Reading zip files: the entries of a zip in memory, and inflating one in a child process.
##
## `zipbytes` reads the central directory and inflates an entry from bytes (zippy only opens a path); `zipchild` inflates in a
## child process that cannot use much memory, because zippy cannot stop at a size and a hostile entry could fill the memory.
## Used for xlsx files and for downloads.

import ../../../core/manifest

const package* = Package(depends: @["bytes", "child"], fragments: @[])

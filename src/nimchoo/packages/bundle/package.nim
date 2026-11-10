## Files built into the program that are also kept in the cache, for the author to edit.
##
## The FIT profile, the licence notice and the page templates are unpacked to the cache directory's `system/` part and never
## overwritten once changed; delete one to get the built-in version again.

import ../../core/manifest

const package* = Package(depends: @["atomic", "cache", "hashing"], fragments: @[])

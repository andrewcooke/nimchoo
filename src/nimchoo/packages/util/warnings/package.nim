## Warnings: oddities in a file that do not stop us reading it.
##
## They are collected, never logged or printed by library code, each with a kind (`WarningKind`) so that they can be counted
## and filtered.  The importer turns them into advisories in its log.

import ../../../core/manifest

const package* = Package(depends: @[], fragments: @[])

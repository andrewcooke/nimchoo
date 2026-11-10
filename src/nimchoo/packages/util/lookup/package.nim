## Table lookups that have to succeed (`must`, `mustMut`).
##
## A lookup that cannot fail is a bug if it does, so these assert instead of raising `KeyError` (CLAUDE.md, error handling).

import ../../../core/manifest

const package* = Package(depends: @[], fragments: @[])

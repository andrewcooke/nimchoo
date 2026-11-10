## A database in a temporary directory and the `Globals` that tab completion uses to read it (read-only, offline), for the
## tests of the providers.

import std/os
import nimchoo/core/globals
import nimchoo/packages/user/session
from nimchoo/registry import allFragments, allAccess

let completionDir* = getTempDir() / "nch-test-completion-providers"

proc freshDb*(name: string): Session =
  ## A new database with the whole schema, open for writing (close it before completing).
  removeDir(completionDir / name)
  openSession(completionDir / name / "x.db", allFragments, access = allAccess)

proc completing*(s: Session, user = ""): Globals =
  ## What `nch __complete` gives the providers, for the database of `s`.
  Globals(
    dbPath: s.path,
    user: user,
    fragments: allFragments,
    access: allAccess,
    offline: true,
    readOnly: true,
  )

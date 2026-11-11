## Check the invariants of tests/support/invariants.nim over a real database,
## read only: `nimble invariants [PATH]` (default: the author's database).

import nimchoo/packages/db/store
import std/[os]
from nimchoo/registry import allAccess, allFragments
import ./support/invariants

proc main() =
  let path =
    if paramCount() > 0:
      paramStr(1)
    else:
      getEnv("HOME") / ".local/share/nch/nch.db"
  # (opened as the program opens it, read only, so that its SQL functions are there; a database made by another version
  # is refused, as everywhere)
  let st = openReadOnly(path, allFragments, allAccess)
  let bad = violations(st.db)
  st.close()
  for line in bad:
    echo line
  if bad.len == 0:
    echo "all invariants hold (" & $allInvariants.len & ")"
  else:
    quit 1

main()

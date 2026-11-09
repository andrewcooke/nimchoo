## Check the invariants of tests/support/invariants.nim over a real database,
## read only: `nimble invariants [PATH]` (default: the author's database).

import nimchoo/db/statement
import std/[os]
import db_connector/db_sqlite
import ./support/invariants

proc main() =
  let path =
    if paramCount() > 0:
      paramStr(1)
    else:
      getEnv("HOME") / ".local/share/nch/nch.db"
  let db = open(path, "", "", "")
  db.execute("pragma query_only = on")
  let bad = violations(db)
  db.close()
  for line in bad:
    echo line
  if bad.len == 0:
    echo "all invariants hold (" & $allInvariants.len & ")"
  else:
    quit 1

main()

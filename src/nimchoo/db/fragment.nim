## The checksum of a fragment (the type and `fragment` are in core/fragment.nim).

import ../core/fragment
import ../hashing

{.push raises: [].}

proc checksum*(f: Fragment): string =
  ## The SHA-256 of the fragment's SQL (and of the version of the data its seed puts in), in
  ## hex: recorded with the fragment when it is applied, so that a database made from
  ## different SQL or different data is noticed when it is opened.
  sha256Hex(
    if f.seedVersion.len > 0:
      f.sql & "\n-- seed data: " & f.seedVersion
    else:
      f.sql
  )

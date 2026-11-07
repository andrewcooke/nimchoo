## The number of a climb among those that share its name (`sector.name_n`, shown as a subscript: "Farellones₃").  Given
## when the climb gets its name and then kept: the next number after the highest one any other climb with that name has
## (retired ones count), so numbers are not reused while the highest holder stays.  Pure SQL on the table.

import db_connector/db_sqlite
import ../db/store
import ../errors

{.push raises: [].}

proc assignNumber*(st: Store, id: int64) {.raises: [StoreError].} =
  ## Give the climb its number among the climbs with its name (as it is now: call this after the name is set).
  guard:
    st.db.exec(
      sql"""update sector set name_n = coalesce((
        select max(s2.name_n) from sector s2
         where s2.id <> sector.id
           and lower(trim(coalesce(nullif(trim(s2.name), ''), 'unnamed'))) =
               lower(trim(coalesce(nullif(trim(sector.name), ''), 'unnamed')))), 0) + 1
      where id = ?""",
      id,
    )

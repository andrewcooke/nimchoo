## The number of a climb among those that share its name (`sector.name_n`, shown as a subscript: "Farellones₃").  Given
## when the climb gets its name and then kept: the next number after the highest one ever given to a climb with that name
## (`sector_name_number` remembers it; retired climbs count), so **a number is never given twice**, even after the climb that had
## it is renamed or deleted, and a climb renamed away and back gets a new one.  Deleting every climb (`clearClimbs`) forgets
## them too, as in a new database.  Names are compared folded (case, accents and
## the spaces at the ends do not matter), and climbs with no name share the group "unnamed".  Pure SQL on the tables.

import ../db/statement
import ../db/store
import ../../core/errors

{.push raises: [].}

proc assignNumber*(st: Store, id: int64) {.raises: [StoreError].} =
  ## Give the climb its number among the climbs with its name (as it is now: call this after the name is set), and remember it
  ## as the highest given for that name.
  st.db.execute(
    """update sector set name_n = max(
        coalesce((select highest from sector_name_number
                   where name = fold(trim(coalesce(nullif(trim(sector.name), ''), 'unnamed')))), 0),
        coalesce((select max(s2.name_n) from sector s2
                   where s2.id <> sector.id
                     and fold(trim(coalesce(nullif(trim(s2.name), ''), 'unnamed'))) =
                         fold(trim(coalesce(nullif(trim(sector.name), ''), 'unnamed')))), 0)) + 1
      where id = :id""",
    id = id,
  )
  st.db.execute(
    """insert into sector_name_number(name, highest)
        select fold(trim(coalesce(nullif(trim(name), ''), 'unnamed'))), name_n from sector where id = :id
        on conflict(name) do update set highest = max(highest, excluded.highest)""",
    id = id,
  )

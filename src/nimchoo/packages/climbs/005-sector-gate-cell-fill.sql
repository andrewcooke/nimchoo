-- (legacy, for a database made before sector_gate_cell: its rows for the sectors that are there; the trigger makes them for the
-- sectors made from now on.  Delete this file at the next squash.)
insert or ignore into sector_gate_cell(sector_id, which, cell)
  select x.id, x.which, cell_shift(x.c, a.v, b.v)
  from (select id, 0 as which, cell(ST_X(StartPoint(route)), ST_Y(StartPoint(route))) as c from sector
        union all select id, 1, cell(ST_X(EndPoint(route)), ST_Y(EndPoint(route))) from sector) x
  join (select -4 as v union all select -3 union all select -2 union all select -1 union all select 0 union all select 1 union all select 2 union all select 3 union all select 4) a on abs(a.v) <= cell_dx(x.c, 0, 100.0)
  join (select -4 as v union all select -3 union all select -2 union all select -1 union all select 0 union all select 1 union all select 2 union all select 3 union all select 4) b on abs(b.v) <= cell_dy(x.c, 0, 100.0)
  where x.c is not null and cell_shift(x.c, a.v, b.v) is not null;

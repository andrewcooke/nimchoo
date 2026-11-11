-- The cells of the grid (geo/cells.nim) round the two gates of a sector: its first point (which 0) and its last (which 1), so
-- that the rides that may have gone over it are found by a join on the integer cell (`route_cell` has the cells of each ride).
-- A gate is a line across the route 25 m each side of the point; a ride that crosses it has a sample within half a gap of
-- the crossing, so the cells within 100 m of the point (a block as many cells either way as 100 m is at the latitude of the
-- point: cell_dx, cell_dy) hold a sample of it unless the gap is over 150 m (a GPS dropout).  The trigger fills it whenever a
-- sector is made, whoever makes it; a route is never changed once made, so nothing else needs to.  Delete 100.0 here and nowhere
-- else to change the margin (and fill it again: `climbs --all --delete -f`, or 005 by hand).
create table sector_gate_cell (
  sector_id integer not null references sector(id) on delete cascade,
  which integer not null check (which in (0, 1)),
  cell integer not null,
  primary key (sector_id, which, cell)) strict, without rowid;
create index sector_gate_cell_cell on sector_gate_cell(cell, which, sector_id);

create trigger sector_gate_cell_made after insert on sector
begin
  insert or ignore into sector_gate_cell(sector_id, which, cell)
  select new.id, g.which, cell_shift(g.c, a.v, b.v)
  from (select 0 as which, cell(ST_X(StartPoint(new.route)), ST_Y(StartPoint(new.route))) as c
        union all select 1, cell(ST_X(EndPoint(new.route)), ST_Y(EndPoint(new.route)))) g
  join (select -4 as v union all select -3 union all select -2 union all select -1 union all select 0 union all select 1 union all select 2 union all select 3 union all select 4) a on abs(a.v) <= cell_dx(g.c, 0, 100.0)
  join (select -4 as v union all select -3 union all select -2 union all select -1 union all select 0 union all select 1 union all select 2 union all select 3 union all select 4) b on abs(b.v) <= cell_dy(g.c, 0, 100.0)
  where g.c is not null and cell_shift(g.c, a.v, b.v) is not null;
end;

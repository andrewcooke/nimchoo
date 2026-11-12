-- Climbs, found in rides and kept, and the times of rides over them.
--
-- A sector is a stretch of road that can be ridden again (now: a climb).  It is shared by all users
-- of the database, so that they can compare.  It is a copy: it has its own route and refers to no
-- ride, so it stays when rides are deleted or imported again.
--
-- The name is text made from the places near the top (see names/), a copy and not a link: null until it is made
-- (the command that finds the climb makes it, or stops), "" if nothing was near it (null again if it could not be made: `--offline`, or no network).
-- manual is 1 for a name the author gave (`nch sector --edit NAME --rename NEW`): the system never changes it.
create table sector (
  id integer primary key,
  length_m real not null,
  gain_m real not null,
  gradient real not null,             -- percent
  category text,                      -- 4, 3, 2, 1 or HC; null if too small to have one
  found_at integer,                   -- Unix seconds: when the ride it was first found on began (a note, not a link)
  name text,
  manual integer not null default 0 check (manual in (0, 1)),
  -- hidden from the lists, as a segment can be hidden on Strava.  Nothing is deleted: it keeps its efforts and its place
  -- in the (n/m) numbering of its name (so that the gap shows), it still takes the efforts of new rides, and it still
  -- counts as a stored climb when a new one is looked for (or the next ride would make it again).
  retired integer not null default 0 check (retired in (0, 1)),
  route blob,
  -- the number among the climbs that share the name ("Farellones₃"): given when the climb gets its name, and kept
  name_n integer not null default 1) strict;
select RecoverGeometryColumn('sector', 'route', 4326, 'LINESTRING', 'XYZ');       -- longitude, latitude, altitude
select CreateSpatialIndex('sector', 'route');

-- One pass of a ride over a sector (a lap is another row).  It belongs to the user of the ride, and
-- goes with the ride or with the sector.  The time is from gate to gate, stops included.
create table effort (
  sector_id integer not null references sector(id) on delete cascade,
  activity_id integer not null references activity(id) on delete cascade,
  start_t real not null,              -- Unix seconds, UTC, interpolated at the start gate
  finish_t real not null,
  elapsed_s real not null,            -- finish_t - start_t
  start_m real not null,              -- metres along the ride at the start gate
  primary key (sector_id, activity_id, start_t)) strict, without rowid;

-- Which activities have been looked at for climbs, and with which version of the method (so that a
-- change of the method shows).  An activity with no positions or no altitude is recorded too: it
-- is not looked at again.
create table climbs_done (
  activity_id integer primary key references activity(id) on delete cascade,
  version integer not null) strict, without rowid;

-- SQLite does not index a foreign key by itself: without this, deleting an activity (and any 'activity_id in (...)') scanned every effort.
create index effort_activity on effort(activity_id);

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

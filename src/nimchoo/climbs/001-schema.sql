-- Climbs, found in rides and kept, and the times of rides over them.
--
-- A sector is a stretch of road that can be ridden again (now: a climb).  It is shared by all users
-- of the database, so that they can compare.  It is a copy: it has its own route and refers to no
-- ride, so it stays when rides are deleted or imported again.
--
-- The name is text made from the places near the top (see names/), a copy and not a link: null until it is made
-- (the command that finds the climb makes it, or stops), "" if nothing was near it (or it was made with --offline).
-- manual is 1 for a name the author gave (`nch sector --edit NAME --rename NEW`): the system never changes it.
create table sector (
  id integer primary key,
  length_m real not null,
  gain_m real not null,
  gradient real not null,             -- percent
  category text,                      -- 4, 3, 2, 1 or HC; null if too small to have one
  found_at integer,                   -- Unix seconds: when the ride it was first found on began (a note, not a link)
  name text,
  manual integer not null default 0 check (manual in (0, 1)));
select AddGeometryColumn('sector', 'route', 4326, 'LINESTRING', 'XYZ');       -- longitude, latitude, altitude
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
  primary key (sector_id, activity_id, start_t)) without rowid;

-- Which activities have been looked at for climbs, and with which version of the method (so that a
-- change of the method shows).  An activity with no positions or no altitude is recorded too: it
-- is not looked at again.
create table climbs_done (
  activity_id integer primary key references activity(id) on delete cascade,
  version integer not null) without rowid;

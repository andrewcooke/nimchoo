-- The tables of the importer module: imported FIT files, the activities in
-- them (one per FIT session), their coordinates and stretches, and the
-- paths already looked at.  Times are Unix seconds UTC, lon/lat degrees
-- (SRID 4326), alt metres.  Everything belongs to a user and goes with them
-- (on delete cascade), which is how `nch --user NAME destroy` works.

create table file (
  id integer primary key,
  user_id integer not null references user(id) on delete cascade,
  name text not null,
  sha256 text not null,
  imported_at integer not null,
  unique (user_id, sha256)) strict;

-- One per FIT session.  (A FIT file has one "activity" message and under it one or
-- more "session" messages, each a stretch of one sport: a triathlon has three.)
-- `session` is its index in the file.  The user is the file's.
create table activity (
  id integer primary key,
  file_id integer not null references file(id) on delete cascade,
  session integer not null,
  start_t integer not null,
  end_t integer not null,
  utc_offset_s integer,
  sport text,
  sub_sport text,
  elapsed_s real,
  timer_s real,
  distance_m real,
  calories integer,
  -- Where it started and what it is called, text made from its route (see names/activity.nim).
  -- null: not named yet (the next `nch import` does it); "": looked at, nothing to say.
  start_place text,
  name text,
  start blob,                -- see below
  unique (file_id, session)) strict;
-- Where the activity started (its first position), for "starts near here".  NULL if the file
-- has no positions.  Written when the activity is imported.
select RecoverGeometryColumn('activity', 'start', 4326, 'POINT', 'XY');
select CreateSpatialIndex('activity', 'start');

create table coords (
  activity_id integer not null references activity(id) on delete cascade,
  t integer not null,
  lon real not null,
  lat real not null,
  alt real,
  primary key (activity_id, t)) strict, without rowid;

-- The stretches of riding of an activity: the times the timer ran (between a timer start and the
-- next stop), with those the device paused by itself and the rider hardly left joined across the
-- pause (importer/stretch.nim).  A stretch is what the climbs are looked for in, so an effort lies
-- within one.  Intervals on the activity's time axis: samples do not refer to them.  Segments of
-- an activity are disjoint and in time order.
create table segment (
  activity_id integer not null references activity(id) on delete cascade,
  n integer not null,
  start_t integer not null,
  end_t integer not null,
  primary key (activity_id, n)) strict, without rowid;

-- The route of an activity as one geometry, a part for each segment, so that
-- "passes near here", GeoJSON and GPX are queries and not scans of coords.  Derived from
-- coords and segment when the activity is imported, in the same transaction.  Parts of
-- fewer than two points are left out, and an activity with no part has no row.  (SpatiaLite
-- cannot put geometry on WITHOUT ROWID tables, so this is an ordinary table.)
create table route (
  activity_id integer primary key references activity(id) on delete cascade,
  geom blob) strict;
select RecoverGeometryColumn('route', 'geom', 4326, 'MULTILINESTRING', 'XY');
select CreateSpatialIndex('route', 'geom');

-- Every path `nch import` has looked at, with the size and modification time it
-- had then.  A path whose size and time have not changed is skipped without
-- reading it.  file_id is set if the file was imported (or is a copy of one that
-- was); failure and message are set instead if it could not be imported.
create table seen_file (
  user_id integer not null references user(id) on delete cascade,
  path text not null,
  size integer not null,
  mtime integer not null,
  file_id integer references file(id) on delete cascade,
  failure text,
  message text,
  primary key (user_id, path)) strict, without rowid;

-- A foreign key needs an index of its own (the primary key starts with the user): deleting a file scanned the table.
create index seen_file_file on seen_file(file_id);

-- Where an activity went, as the cells of a grid (geo/cells.nim; in SQL the function cell(lon, lat)): one row for each
-- visit, a run of consecutive samples in one cell, with the times of its first and last sample.  Questions about places (what is
-- near a route, which rides pass a climb, a heat map) are joins on the integer cell.  Written by the importer from the
-- samples, in the same transaction as them (importer/visits.nim).  Visits of an activity do not overlap in time.
create table route_cell (
  activity_id integer not null references activity(id) on delete cascade,
  cell integer not null,
  t_in integer not null,
  t_out integer not null,
  primary key (activity_id, t_in)) strict, without rowid;
create index route_cell_cell on route_cell(cell, activity_id);

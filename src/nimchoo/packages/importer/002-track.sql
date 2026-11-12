-- The positions of an activity as arrays (importer/series.nim), one row for the activity: the times as offsets in seconds from
-- t0, the longitudes and latitudes in FIT semicircles (int32), the altitudes in 0.2 m from -500 m (uint16), all little-endian.
-- Written once at import after the positions are cleaned (importer/clean.nim), and never changed.
create table track (
  activity_id integer primary key references activity(id) on delete cascade,
  t0 integer not null,                -- the time of the first position
  t1 integer not null,                -- the time of the last
  n integer not null,
  t blob not null,
  lon blob not null,
  lat blob not null,
  alt blob not null) strict;

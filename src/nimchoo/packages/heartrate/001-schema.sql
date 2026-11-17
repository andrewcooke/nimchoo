-- The heart rate of an activity as arrays (heartrate/series.nim), one row for the activity: the times as offsets in seconds from
-- t0 (int32) and the beats per minute (uint8), little-endian.  Written once at import, and never changed.
create table heartrate_series (
  activity_id integer primary key references activity(id) on delete cascade,
  t0 integer not null,
  n integer not null,
  t blob not null,
  bpm blob not null) strict;

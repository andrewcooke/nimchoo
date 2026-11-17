-- The name of each activity that has been named: where it started and what it is called, text made by the namers
-- (naming.nim).  An activity with no row has not been named yet (the next `nch import` does it); "": looked at, nothing to say.
create table activity_name (
  activity_id integer primary key references activity(id) on delete cascade,
  start_place text not null,
  name text not null) strict;

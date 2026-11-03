-- Heart rate: one reading per second at most, kept with the activity it was recorded in.
create table heartrate (
  activity_id integer not null references activity(id) on delete cascade,
  t integer not null,                 -- Unix seconds, UTC
  bpm integer not null,
  primary key (activity_id, t)) without rowid;

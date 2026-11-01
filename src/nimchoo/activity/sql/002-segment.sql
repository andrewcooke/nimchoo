-- The stretches of an activity during which the timer ran (between a timer
-- start and the next stop).  Intervals on the activity's time axis: samples do
-- not refer to them.  Segments of an activity are disjoint and in time order.

create table segment (
  activity_id integer not null references activity(id),
  n integer not null,
  start_t integer not null,
  end_t integer not null,
  primary key (activity_id, n)) without rowid;

-- The channels of an activity (channels/kinds.nim: heart rate, cadence, temperature, power, speed, distance) as arrays
-- (channels/series.nim), a row for each activity and channel it has: the times as gaps in seconds, each from the reading
-- before (the first from start_epoch, so 0), in unsigned LEB128 (a byte a gap under two minutes), and the readings, each
-- packed as its channel says (its packing and step are in the code's list, not here, so that a channel is added without a
-- fragment).  Written once at import, and never changed.
create table channel_series (
  activity_id integer not null references activity(id) on delete cascade,
  channel text not null,          -- its name in the list: 'heart_rate', 'cadence' ...
  start_epoch integer not null,   -- the time of the first reading
  n_readings integer not null,
  gaps_s blob not null,
  readings blob not null,
  primary key (activity_id, channel)) strict, without rowid;

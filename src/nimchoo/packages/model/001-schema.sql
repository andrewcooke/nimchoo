-- The variables of the training-impulse calculation, as named sets (models), and the impulses
-- made with them.  A model is never edited once it exists (a new one is added), because the
-- impulses made with it would no longer match.  Models belong to no user.
create table ff_model (
  id integer primary key,
  name text not null unique,                        -- for display
  -- the impulse of an instant: ((zone - zero) / (one - zero)) ^ gamma, clipped at 0
  gamma real not null check (gamma > 0),
  zero real not null,
  one real not null,
  max_secs integer not null check (max_secs > 0),   -- the longest gap in heart rate that is bridged
  -- the upper limits of heart-rate zones 1 to 5, as percentages of the threshold heart rate
  zone1 real not null,
  zone2 real not null,
  zone3 real not null,
  zone4 real not null,
  zone5 real not null,
  -- the decay time of the curves made from the impulses
  fitness_days real not null check (fitness_days > 0),
  fatigue_days real not null check (fatigue_days > 0),
  check (zero < one),
  check (0 < zone1 and zone1 < zone2 and zone2 < zone3 and zone3 < zone4 and zone4 < zone5)) strict;

-- The impulse of an activity in each hour (Unix seconds at the start of the hour, UTC), in
-- units of "per 10 seconds".  An activity with heart rate has a row for each hour the heart
-- rate covers (zero if it never rose above the zero level); one without, or of a user with
-- no threshold heart rate, has none.
create table impulse (
  activity_id integer not null references activity(id) on delete cascade,
  model_id integer not null references ff_model(id) on delete cascade,
  hour_t integer not null,
  value real not null check (value >= 0),
  primary key (activity_id, model_id, hour_t)) strict, without rowid;

-- Every impulse depends on the user's threshold heart rate, so if it changes (a very rare
-- event) the user's impulses go and are calculated again from scratch.
create trigger impulse_fthr_changed after update of fthr on user_profile
when old.fthr is not new.fthr
begin
  delete from impulse where activity_id in (
    select a.id from activity a join file f on f.id = a.file_id where f.user_id = new.user_id);
end;

-- A foreign key needs an index of its own (the primary key starts with the activity): deleting a model scanned the table.
create index impulse_model on impulse(model_id);

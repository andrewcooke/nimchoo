-- The models: named sets of the variables of the training impulse and of the fitness and
-- fatigue curves made from it, with the tags of the activities that count (see calc.nim).
-- Models belong to no user.  A built-in model (made by the program: `default`) is selected for
-- every user from the start; otherwise it is a model like the others (edited and deleted with
-- `nch ff`; a rebuild makes it again).
create table ff_model (
  id integer primary key,
  name text not null,
  folded text not null unique,                      -- the name as it is matched: lower case, no accents
  built_in integer not null default 0 check (built_in in (0, 1)),
  -- the impulse of an instant: ((zone - zero) / (one - zero)) ^ gamma, clipped at 0
  gamma real not null check (gamma > 0),
  zero real not null,
  one real not null,
  max_gap_s integer not null check (max_gap_s > 0), -- the longest gap in heart rate that is bridged
  -- the upper limits of heart-rate zones 1 to 5, as percentages of the threshold heart rate
  zone1 real not null,
  zone2 real not null,
  zone3 real not null,
  zone4 real not null,
  zone5 real not null,
  -- readings above this (a percentage of the threshold heart rate) are a fault of the sensor, not a heart: ignored
  ceiling real not null,
  -- the decay times of the curves made from the impulses, and their weights in form
  -- (form = fitness_scale * fitness - fatigue_scale * fatigue)
  fitness_days real not null check (fitness_days > 0),
  fatigue_days real not null check (fatigue_days > 0),
  fitness_scale real not null check (fitness_scale > 0),
  fatigue_scale real not null check (fatigue_scale > 0),
  check (zero < one),
  check (0 < zone1 and zone1 < zone2 and zone2 < zone3 and zone3 < zone4 and zone4 < zone5),
  check (zone5 < ceiling)) strict;

-- Which activities count in a model: those with a tag matching every pattern (as `--tags` of
-- `nch activities` matches; `folded` is the pattern as it is matched).  A model with none
-- counts every activity.
create table ff_model_pattern (
  model_id integer not null references ff_model(id) on delete cascade,
  pattern text not null,
  folded text not null,
  primary key (model_id, folded)) strict, without rowid;

-- The models a user has chosen: the models subject (`nch ff CRITERIA --select`), as
-- `activity_selection` is the activities'.  The built-in models are selected for every user
-- from the start (the trigger below, and the seed for the users there are already).
create table model_selection (
  user_id integer not null references user(id) on delete cascade,
  model_id integer not null references ff_model(id) on delete cascade,
  primary key (user_id, model_id)) strict, without rowid;

-- A foreign key needs an index of its own (the primary key starts with the user).
create index model_selection_model on model_selection(model_id);

create trigger model_selection_new_user after insert on user
begin
  insert into model_selection(user_id, model_id) select new.id, id from ff_model where built_in = 1;
end;

-- The impulse of each stretch of riding of an activity (`segment`, its `n`), as one lump at
-- its centre (`centre_epoch`: Unix seconds, the time weighted by the impulse), in units of "per 10
-- seconds" (see calc.nim).  An activity with heart rate has a row for each of its stretches (zero,
-- at the stretch's middle, if the heart rate never rose above the zero level there), so that a
-- row says it was worked out; one without heart rate, or of a user with no threshold heart rate,
-- has none.
create table impulse (
  activity_id integer not null references activity(id) on delete cascade,
  model_id integer not null references ff_model(id) on delete cascade,
  n integer not null,
  centre_epoch integer not null,
  value real not null check (value >= 0),
  primary key (activity_id, model_id, n)) strict, without rowid;

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

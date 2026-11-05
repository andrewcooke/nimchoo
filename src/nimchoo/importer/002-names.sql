-- Where an activity started and what it is called, both text made from its route (see names/activity.nim).
-- null: not named yet (the next `nch import` does it); "": looked at, nothing to say (or made with --offline).
alter table activity add column start_place text;
alter table activity add column name text;

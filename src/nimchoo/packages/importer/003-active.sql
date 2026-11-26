-- The file's timer total goes (2026-11-26): an activity's active time is worked out from its riding and its breaks
-- (importer/active.nim), and `distance_m` is ours too, from the records (importer/extract.distanceOf).
alter table activity drop column timer_s;

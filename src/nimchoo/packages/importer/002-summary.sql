-- What an activity kept of its file's summary that is not ours or that nothing read (2026-11-26): the sport is its
-- `sport:` tag (tags/sport.nim), the elapsed time is end_epoch - start_epoch, and the calories and the device's offset
-- from UTC were never read.
alter table activity drop column utc_offset_s;
alter table activity drop column sport;
alter table activity drop column sub_sport;
alter table activity drop column elapsed_s;
alter table activity drop column calories;

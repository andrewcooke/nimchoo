-- A climb's number among the climbs that share its name, kept: "Farellones₃" is always the same climb.  It used to be worked
-- out when shown (the rank by gain, "(n/m)"), so it moved when climbs were found, retired or renamed.  Now it is given when a
-- climb gets its name (the next number among those that have the name) and stays.  The numbers that were on the screen when
-- this was made are the ones kept.
alter table sector add column name_n integer not null default 1;
update sector set name_n = (
  select count(*) + 1 from sector s2
   where lower(trim(coalesce(nullif(trim(s2.name), ''), 'unnamed'))) = lower(trim(coalesce(nullif(trim(sector.name), ''), 'unnamed')))
     and (s2.gain_m > sector.gain_m or (s2.gain_m = sector.gain_m and s2.id < sector.id)));

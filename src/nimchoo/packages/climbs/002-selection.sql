-- The climbs a user has chosen: the climbs subject (`nch climbs CRITERIA --select`, and an import, which chooses the climbs of
-- the activities it imported), as `selection` is the activities'.  Rows belong to the user whose selection it is; the climbs
-- are shared.  Replaced as a whole.
create table climb_selection (
  user_id integer not null references user(id) on delete cascade,
  sector_id integer not null references sector(id) on delete cascade,
  primary key (user_id, sector_id)) strict, without rowid;

-- A foreign key needs an index of its own (the primary key starts with the user): deleting the climbs scanned the selections.
create index climb_selection_sector on climb_selection(sector_id);

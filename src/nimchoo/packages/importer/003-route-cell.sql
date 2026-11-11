-- Where an activity went, as the cells of a grid (geo/cells.nim; in SQL the function cell(lon, lat)): one row for each
-- visit, a run of consecutive samples in one cell, with the times of its first and last sample.  Questions about places (what is
-- near a route, which rides pass a climb, a heat map) are joins on the integer cell.  Written by the importer from the
-- samples, in the same transaction as them (importer/visits.nim).  Visits of an activity do not overlap in time.
create table route_cell (
  activity_id integer not null references activity(id) on delete cascade,
  cell integer not null,
  t_in integer not null,
  t_out integer not null,
  primary key (activity_id, t_in)) strict, without rowid;
create index route_cell_cell on route_cell(cell, activity_id);

-- Names are read by cells (a degree by a degree) and every feature of a cell is kept, whatever its kind: see features.nim.
-- `coverage` says which cells of which country have been read; `name_source` (whole countries) and the features read
-- under the old rules are forgotten, and read again as cells are wanted.
drop table name_source;
delete from feature;
create table coverage (
  country text not null references country(iso) on delete cascade,
  cell_lon integer not null,                -- whole degrees, south-west corner
  cell_lat integer not null,
  loaded_at integer not null,               -- Unix seconds
  features integer not null,                -- how many the cell gave
  primary key (country, cell_lon, cell_lat)) without rowid;

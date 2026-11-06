-- Which countries touch each cell of the map (a quarter of a degree of longitude by a quarter of a degree of latitude,
-- named by the south-west corner, in quarter degrees: cell_lon 4 * -71 = -284 is the cell from 71 degrees west).  Worked
-- out from the outlines in `country` the first time a cell is wanted, and kept: "which countries are there round here?"
-- is then a lookup and no geometry is done.  A cell on a border lists both countries; a cell of open sea is in
-- `country_cell_done` and lists none.
create table country_cell_done (
  cell_lon integer not null,
  cell_lat integer not null,
  primary key (cell_lon, cell_lat)) strict, without rowid;

create table country_cell (
  cell_lon integer not null,
  cell_lat integer not null,
  country text not null references country(iso) on delete cascade,
  primary key (cell_lon, cell_lat, country)) strict, without rowid;

-- The outlines now come from Natural Earth (the GeoNames ones were invalid for GEOS).  A database made before has the old
-- ones: forget them, and they are read again from the new source the next time they are wanted (the countries, their
-- places and the cells already read are kept).
update country set geom = null;

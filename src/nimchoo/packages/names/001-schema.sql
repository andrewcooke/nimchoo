-- Names of places, for naming climbs and activities.
--
-- The countries come from the outlines GeoNames publishes (fetched the first time they are wanted:
-- see names/countries.nim).  A country's names are read from its GeoNames file (fetched when a name is
-- wanted there), a cell at a time, into `feature`.
create table country (
  iso text primary key,
  name text not null,
  geoname_id integer not null,
  geom blob) strict;              -- no outline for a few small territories: the geometry is null
select RecoverGeometryColumn('country', 'geom', 4326, 'MULTIPOLYGON', 'XY');
select CreateSpatialIndex('country', 'geom');

-- Which cells (a degree of longitude by a degree of latitude, named by the south-west corner) of which country have
-- been read from the country's file into `feature`, when, and how many features that gave.  A cell is read when a name
-- is wanted in it (see names/features.nim).
create table coverage (
  country text not null references country(iso) on delete cascade,
  cell_lon integer not null,                -- whole degrees, south-west corner
  cell_lat integer not null,
  loaded_at integer not null,               -- Unix seconds
  features integer not null,                -- how many the cell gave
  primary key (country, cell_lon, cell_lat)) strict, without rowid;

-- The features of the cells read, of every class and kind (peaks, passes, towns, farms, streams ...): what counts as a
-- name is decided by the rules that use them.  id is the GeoNames id; class and code are GeoNames' (PASS, PK, MT, PPL ...).
create table feature (
  id integer primary key,
  country text not null references country(iso) on delete cascade,
  name text not null,
  class text not null,
  code text not null,
  population integer,
  geom blob) strict;
select RecoverGeometryColumn('feature', 'geom', 4326, 'POINT', 'XY');
select CreateSpatialIndex('feature', 'geom');
create index feature_country on feature(country);

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

-- A foreign key needs an index of its own (the primary key starts with the cell): deleting a country scanned the table.
create index country_cell_country on country_cell(country);

-- Names of the author's own for places (a landmark: a position and a radius).  They come before everything GeoNames
-- knows when something is named: a climb that tops out, or a ride that turns round, inside the radius is called by the
-- landmark's name.  Shared by all users, like the climbs.
create table landmark (
  id integer primary key,
  name text not null unique,
  lon real not null,
  lat real not null,
  radius_m real not null) strict;

-- Names of places, for naming climbs and activities.
--
-- The countries come from the outlines GeoNames publishes (fetched the first time they are wanted:
-- see names/countries.nim).  A country's names are read from its GeoNames file (fetched when a name is
-- wanted there), a cell at a time, into `feature`.
create table country (
  iso text primary key,
  name text not null,
  geoname_id integer not null);              -- no outline for a few small territories: the geometry is null
select AddGeometryColumn('country', 'geom', 4326, 'MULTIPOLYGON', 'XY');
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
  primary key (country, cell_lon, cell_lat)) without rowid;

-- The features of the cells read, of every class and kind (peaks, passes, towns, farms, streams ...): what counts as a
-- name is decided by the rules that use them.  id is the GeoNames id; class and code are GeoNames' (PASS, PK, MT, PPL ...).
create table feature (
  id integer primary key,
  country text not null references country(iso) on delete cascade,
  name text not null,
  class text not null,
  code text not null,
  population integer);
select AddGeometryColumn('feature', 'geom', 4326, 'POINT', 'XY');
select CreateSpatialIndex('feature', 'geom');
create index feature_country on feature(country);

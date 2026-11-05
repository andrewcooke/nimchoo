-- Names of places, for naming climbs and (later) where activities start.
--
-- The countries come from the outlines GeoNames publishes (fetched the first time they are wanted:
-- see names/countries.nim).  A country's names are read from its GeoNames file (fetched when a name is
-- wanted there) into `feature`, and `name_source` records which countries are in.
create table country (
  iso text primary key,
  name text not null,
  geoname_id integer not null);              -- no outline for a few small territories: the geometry is null
select AddGeometryColumn('country', 'geom', 4326, 'MULTIPOLYGON', 'XY');
select CreateSpatialIndex('country', 'geom');

-- Which countries' files have been read into `feature`, when, and how many features that gave.
create table name_source (
  country text primary key references country(iso) on delete cascade,
  loaded_at integer not null,              -- Unix seconds
  features integer not null) without rowid;

-- The terrain features (class T: mountains, hills, peaks, passes...) and populated places (class P) of the
-- countries loaded.  id is the GeoNames id; class and code are GeoNames' (PASS, PK, MT, HLL, PPL...).
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

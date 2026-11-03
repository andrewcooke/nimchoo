-- Places: towns and cities of the world (and, later, places the user names), each a point.
-- Not owned by a user: it is the same for everyone, and `destroy --user` leaves it alone.
-- `source` says where a row came from: 'geonames' (the list the program carries, loaded when
-- the database is made: see seed.nim) or 'user'.  `country` is the ISO 3166 two-letter code.
-- The spatial index is made by the loading code, after the rows are in (five times faster
-- than maintaining it row by row).
create table place (
  id integer primary key,
  name text not null,
  country text not null,
  population integer not null default 0,
  source text not null);
select AddGeometryColumn('place', 'geom', 4326, 'POINT', 'XY');

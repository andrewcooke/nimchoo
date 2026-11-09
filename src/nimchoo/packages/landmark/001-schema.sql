-- Names of the author's own for places (a landmark: a position and a radius).  They come before everything GeoNames
-- knows when something is named: a climb that tops out, or a ride that turns round, inside the radius is called by the
-- landmark's name.  Shared by all users, like the climbs.
create table landmark (
  id integer primary key,
  name text not null unique,
  lon real not null,
  lat real not null,
  radius_m real not null) strict;

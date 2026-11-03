-- The database's own tables.  The user: very lightweight (people sharing a
-- computer).  Every activity belongs to one, through its file.  Lives with the
-- database code because every module's data hangs off it.
-- Exactly one user is the default: the one commands work on without --user.  The first
-- user (made when the database is created) is; `nch user --default` moves it.
create table user (
  id integer primary key,
  name text not null unique,
  is_default integer not null default 0 check (is_default in (0, 1)));
create unique index user_default on user(is_default) where is_default = 1;

-- SpatiaLite's bookkeeping (its tables of coordinate systems and geometry
-- columns), so that any module can have geometry columns.  Only WGS84 (the
-- SRID of GPS coordinates, 4326) is loaded.  0: we are already in a transaction.
select InitSpatialMetadata(0, 'WGS84');

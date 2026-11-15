-- What a view needs to know whether the data it was made from have changed (dev/display-arch/plan.md, step 2): the identity
-- of this database, and a counter for each table, kept by triggers (made by `db/versions.nim` for every table a package owns).

-- One row: a random name for this database, made when it is created, so that a key made from one database is never the
-- key of another.
create table database_identity (
  one integer not null primary key check (one = 1),
  id text not null
) strict;

-- The number of times each table has been inserted into, updated or deleted from: a key of "what is in the table now".
create table table_version (
  name text not null primary key,
  version integer not null
) strict, without rowid;

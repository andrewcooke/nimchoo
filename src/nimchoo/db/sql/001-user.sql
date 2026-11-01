-- The user: very lightweight (people sharing a computer).  Every activity
-- belongs to one.  Lives with the database code because every module's data
-- hangs off it.
create table user (
  id integer primary key,
  name text not null unique);

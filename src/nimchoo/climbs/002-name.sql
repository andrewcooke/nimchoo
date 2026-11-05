-- A name for a sector, from the places near it (see names/): text, a copy, not a link.  name_checked is 1 once
-- the names have been looked at, whether or not one was found (so that it is not looked at again); 0 until then.
alter table sector add column name text;
alter table sector add column name_checked integer not null default 0;

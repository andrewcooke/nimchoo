-- The highest number ever given to a climb of each name (the name folded as the numbering folds it: `ordinal.nim`), so that a
-- number is not given again when the climb that had it is renamed or deleted.
create table sector_name_number (
  name text not null primary key,
  highest integer not null) strict, without rowid;

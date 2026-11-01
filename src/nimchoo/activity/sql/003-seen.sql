-- Every path `nch import` has looked at, with the size and modification time it
-- had then.  A path whose size and time have not changed is skipped without
-- reading it.  file_id is set if the file was imported (or is a copy of one that
-- was); failure and message are set instead if it could not be imported.

create table seen_file (
  user_id integer not null references user(id),
  path text not null,
  size integer not null,
  mtime integer not null,
  file_id integer references file(id),
  failure text,
  message text,
  primary key (user_id, path)) without rowid;

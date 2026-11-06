-- The current selection of a user: the activities that commands which work on "the
-- selection" (maps, exports, ...) use.  Rows belong to the user whose selection it is, and
-- may point at activities of other users.  Replaced as a whole by each `nch select`.
create table selection (
  user_id integer not null references user(id) on delete cascade,
  activity_id integer not null references activity(id) on delete cascade,
  primary key (user_id, activity_id)) strict, without rowid;

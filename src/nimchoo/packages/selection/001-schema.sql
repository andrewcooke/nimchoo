-- The current selection of a user: the activities that commands which work on "the
-- selection" (maps, exports, ...) use.  Rows belong to the user whose selection it is, and
-- may point at activities of other users.  Replaced by `nch activities --select` and by an import.
create table activity_selection (
  user_id integer not null references user(id) on delete cascade,
  activity_id integer not null references activity(id) on delete cascade,
  primary key (user_id, activity_id)) strict, without rowid;

-- A foreign key needs an index of its own (the primary key starts with the user): deleting an activity scanned the selections.
create index activity_selection_activity on activity_selection(activity_id);

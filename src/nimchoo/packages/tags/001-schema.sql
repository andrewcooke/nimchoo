-- The tags of the activities (tags/tag.nim): each as it was given, and folded (lower case, no accents: what is matched).
-- One row for each tag of an activity; two that fold the same are one.  They go when the activity does.
create table activity_tag (
  activity_id integer not null references activity(id) on delete cascade,
  tag text not null,
  folded text not null,
  primary key (activity_id, folded)) strict, without rowid;
-- (the activities that have a tag: a pattern without `*` at its start uses it)
create index activity_tag_folded on activity_tag(folded, activity_id);

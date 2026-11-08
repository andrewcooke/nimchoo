-- SQLite does not index a foreign key by itself: without this, deleting an activity (and any 'activity_id in (...)') scanned every effort.
create index effort_activity on effort(activity_id);

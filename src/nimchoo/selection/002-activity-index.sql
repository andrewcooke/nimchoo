-- A foreign key needs an index of its own (the primary key starts with the user): deleting an activity scanned the selections.
create index selection_activity on selection(activity_id);

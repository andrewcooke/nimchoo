-- A foreign key needs an index of its own (the primary key starts with the user): deleting a file scanned the table.
create index seen_file_file on seen_file(file_id);

-- A foreign key needs an index of its own (the primary key starts with the activity): deleting a model scanned the table.
create index impulse_model on impulse(model_id);

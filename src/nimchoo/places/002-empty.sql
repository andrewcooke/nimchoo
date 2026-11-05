-- The list of towns and cities the program used to carry is gone (the names come from the GeoNames files, see names/).
-- The table stays, empty and unused, because activity.place_id refers to it and SQLite cannot drop a column that has a
-- foreign key without rebuilding the table; both can go the next time `activity` is rebuilt for another reason.
delete from place;

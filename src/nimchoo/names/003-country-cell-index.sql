-- A foreign key needs an index of its own (the primary key starts with the cell): deleting a country scanned the table.
create index country_cell_country on country_cell(country);

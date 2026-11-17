-- The names of activities belong to the package `naming` now (its table `activity_name`, made from the namers after each
-- import), not to the activities: the columns go.  An existing database is named again by the next `nch import`.
alter table activity drop column start_place;
alter table activity drop column name;

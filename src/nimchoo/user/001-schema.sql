-- What is known about a user for training calculations (see TODO.md, Task 7): one row per user,
-- made when a value is first set.  `fthr` is the functional threshold heart rate in bpm (the
-- highest rate the user can sustain for about an hour), from which heart-rate zones are made.
-- One value, with no history: changing it is a rare event that means starting the calculations
-- again.  The user itself (and its name) is in the `user` table of the database module.
create table user_profile (
  user_id integer primary key references user(id) on delete cascade,
  fthr integer);

-- The user: very lightweight (people sharing a computer).  Every activity belongs to one, through its file; every
-- package's per-user table refers to this one.
-- Exactly one user is the default: the one commands work on without --user.  The first user (made when the
-- database is first opened by a session) is; `nch users --default` moves it.
create table user (
  id integer primary key,
  name text not null unique,
  is_default integer not null default 0 check (is_default in (0, 1))) strict;
create unique index user_default on user(is_default) where is_default = 1;

-- What is known about a user for training calculations (see TODO.md, Task 7): one row per user,
-- made when a value is first set.  `fthr` is the functional threshold heart rate in bpm (the
-- highest rate the user can sustain for about an hour), from which heart-rate zones are made.
-- One value, with no history: changing it is a rare event that means starting the calculations
-- again.  The user itself (and its name) is the table above.
create table user_profile (
  user_id integer primary key references user(id) on delete cascade,
  fthr integer) strict;

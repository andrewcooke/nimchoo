-- A climb can be retired: hidden from the lists, as a segment can be hidden on Strava.  Nothing is deleted: it keeps its
-- efforts and its place in the (n/m) numbering of its name (so that the gap shows), it still takes the efforts of new
-- rides, and it still counts as a stored climb when a new one is looked for (or the next ride would make it again).
-- `nch sector --edit NAME --retire` and `--unretire`.
alter table sector add column retired integer not null default 0 check (retired in (0, 1));

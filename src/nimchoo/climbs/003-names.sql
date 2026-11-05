-- Names set by hand, and a new start for the automatic ones.
--
-- manual is 1 for a name the author gave (`nch sector --edit NAME --rename NEW`): the system never changes it.
alter table sector add column manual integer not null default 0;

-- The rules for the automatic names changed (the end first, then the middle, and the kind of feature taken into
-- account): the names given so far are forgotten, and the next `nch climbs` names the sectors again.  None is
-- manual yet.
update sector set name = null, name_checked = 0;

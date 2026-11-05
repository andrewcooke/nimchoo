-- A sector is named when it is found, or the command stops: there is no "looked at but not named yet" state.
-- name is null only for a sector not named yet (the next `nch climbs` names it); "" is a sector with nothing near it
-- (or one made with --offline), and stays.
update sector set name = '' where name is null and name_checked = 1;
alter table sector drop column name_checked;

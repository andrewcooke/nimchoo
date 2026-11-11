-- (legacy, for a database made before route_cell: its rows from coords.  A new database has no coords yet, so this does
-- nothing; the same visits are written from Nim at import.  Delete this file at the next squash.)
insert into route_cell(activity_id, cell, t_in, t_out)
with c as (select activity_id, t, cell(lon, lat) as cell from coords),
v as (select activity_id, t, cell from c where cell is not null),
r as (select activity_id, t, cell,
        row_number() over (partition by activity_id order by t)
        - row_number() over (partition by activity_id, cell order by t) as grp from v)
select activity_id, cell, min(t), max(t) from r group by activity_id, cell, grp;

-- sector.kind was never read (every sector is a climb).  When another kind of sector exists, how to tell
-- them apart is decided then (a column, or a table for each).
alter table sector drop column kind;

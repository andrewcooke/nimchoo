-- More kinds of feature are kept (areas, water, more terrain): the features and the record of which countries were
-- loaded are forgotten, and the next use of a country reads its file again (it is in the cache: no download).
delete from feature;
delete from name_source;

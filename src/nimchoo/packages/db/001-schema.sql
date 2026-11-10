-- The database's own: SpatiaLite's metadata, so that any package can have geometry columns.  (The user, which
-- every package's data hangs off, is the `user` package's.)

-- SpatiaLite's bookkeeping (its tables of coordinate systems and geometry
-- columns), so that any module can have geometry columns.  Only WGS84 (the
-- SRID of GPS coordinates, 4326) is loaded.  0: we are already in a transaction.
select InitSpatialMetadata(0, 'WGS84');

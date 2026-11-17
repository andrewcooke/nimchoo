-- The counters of 002-versions.sql are dropped (2026-11-16): views are made on every request and nothing is cached, so
-- nothing reads them (dev/HISTORY.md).  The triggers that kept them are dropped by this fragment's seed
-- (`versions.dropCounters`), since their names come from the tables a database has.  Both fragments go at the next squash.
drop table table_version;
drop table database_identity;

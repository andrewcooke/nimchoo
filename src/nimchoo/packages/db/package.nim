## The database: opening it, its schema as fragments, and the statements that touch it.
##
## * **Fragments (migrations).**  The structure is described by SQL files, `NNN-name.sql` in the directory of the package that
##   owns the tables, listed in that package's `package.nim`; the registry joins them, each package after those it depends
##   on.  The SQL is read when the program is compiled, so it is inside the `nch` binary.  Opening a database applies the
##   fragments it has not had, each in a transaction, and records them in the table `fragment` (name, applied_at, sha256).
##   A fragment that is recorded with another checksum is refused ("made by a different version of nch"), and so is one the
##   program does not have ("from a newer version"); the message says to start again with `nch db --delete -f`.
##   **Never edit a fragment that any database has had, and never delete one**: add a numbered file (`alter table`, `update`).
##   SQLite cannot drop a column that has a foreign key or an index without rebuilding the table.  Fragments are plain DDL;
##   data is inserted from Nim (a fragment may have a seed).  Every table must say `strict`.  A geometry column is declared
##   `blob` and registered with `RecoverGeometryColumn(table, column, 4326, 'POINT', 'XY')`, because SpatiaLite's
##   `AddGeometryColumn` does not work on a strict table.  New files are made with `auto_vacuum = incremental`; `reclaim`
##   gives the space back after a big delete.
## * **Squashing (decided 2026-11-05).**  While only the author has a database, at a milestone, each package's fragments may
##   be merged into its `001-schema.sql` and the database rebuilt (`nch db --delete -f`, then import again; the cache
##   survives).  Once anyone else has a database, never squash again.  Before deleting the old fragments compare the schema
##   they make with the squashed one (every table, column, index and foreign key, from a fresh database each way).  What a
##   rebuild loses that cannot be made again from the FIT files: the users and their FTHR, models, the saved selection,
##   the landmarks and names given by hand.
## * **Statements.**  Values are bound by name (`query(db, T, "... where id = :id", id = 3)`), never put into the text; a `?`
##   is a compile error.  A query built from pieces is an `Sql` (`sqltext`), which also records the packages whose files wrote
##   its pieces.  Rows are read into typed tuples or objects.  Nothing else imports `db_connector`.
## * **Access.**  SQLite's authorizer asks, for every statement as it is prepared, whether the package of the file it is
##   written in may touch each table (`access`): a package may write only its own tables and read those of the packages it
##   depends on; a breach is a `StoreError` naming the package, the table and the SQL.  A piece contributed by another
##   package may be read, but cannot make the runner write.
## * The `db` package owns the table `fragment` and SpatiaLite's metadata.  The user is the `user` package's.  `nch db` says
##   where the database is and how big; `nch db --delete -f` deletes it.

import ../../core/manifest
import ./command

const package* = Package(
  depends: @["args", "confirm", "fold", "hashing", "lookup", "ui"],
  fragments: @[],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "the database file: where it is and how big, or delete it",
      run: command.run,
      options: command.options,
    )
  ],
)

## The users, and which one a command works for.
##
## Very lightweight: people sharing a computer.  This package owns the tables `user` and `user_profile` (the user's threshold
## heart rate, `fthr`), and every other package's per-user table refers to `user` and so depends on this package.  Exactly one
## user is the default, the one a command works on without `--user`; the first is made when a database is first opened, and
## if the default is deleted another becomes it.  Deleting a user deletes everything they have, by `on delete cascade`
## (`wipe.userTables` lists the tables, and a test checks that none is forgotten).
##
## * `openSession` finds the user a command works for and gives a `Session` (the store, the user's id and name); a `Session`
##   converts to a `Store`, so only code that needs the user says `Session`.
## * `nch users` is a command of this package: make, rename, set the FTHR of users, choose the default, delete.  A user's name
##   is the key for `--user`, and users are never made by accident (`--add`).  Changing an FTHR makes `model` work its
##   impulses out again, by a trigger of its own.
## * The extension point `user/has`: the packages whose data hangs off a user contribute a count with its name (`importer`:
##   the activities).  `nch users` shows each as a column and says them when it asks before a delete.

import ../../core/manifest
import ./[command, has]

const package* = Package(
  depends: @["args", "confirm", "db", "ui"],
  fragments: @[
    fragment("001-schema.sql") # user, user_profile
  ],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "the users: make, rename, set the threshold heart rate",
      run: command.run,
      options: command.options,
    )
  ],
  defines: @[
    PointDecl(
      name: userHas.name,
      summary:
        "what packages say a user has, for `nch users`: a count with its name (the activities)",
    )
  ],
)

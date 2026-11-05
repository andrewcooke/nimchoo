
# nimchoo

this project is a reworking of choochoo (which can usually be found in
the choochoo directory parallel to this one).  what i want to do is:

* simplify choochoo hugely.  instead of a monolithic web service it
  will be a collection of lightweight tools.

* simplify the database schema (now i understand postgres better)

* simplify how data are displayed.

* move from python to a more modern, more powerful language (with an
  emphasis on functional programming).

* extend tests.

* use ai for development.

## TODO.md

you will track what we are doing via the file TODO.md in the nimchoo
directory.

## rules

a few rules to guide behavior:

* i will generally discuss a change before implementing it.  don't
  switch from discussion to implementation without my approval.

* while this account has sudo privileges you MUST NOT use sudo
  yourself.  instead, ask me to execute commands that require sudo
  access.

* we are working on a newly installed VM so common commands may be
  missing.  ask me if you want me to install anything.

## language choice

i would like to try using nim and have installed the compiler etc.

## general structure

hopefully development will proceed in modules (or packages, or
whatever nim uses).  some of these will be to generate output (more on
this below), while others will be to add extra processing or extend
data import.  often (but typically not in the case of extending data
import) these will correspond to different (sub-)commands (and new
tables in the database).

as much as possible each "chunk" of functionality should be
independent.  so, for example, it would be nice if each module that
extended data import had its own fragment of sql, ideally in a file
consisting only of ddl instructions, and the database as a whole is
made by applying these files in order.

each command lives with the code it is built on, in one directory
(a module): the command itself, its logic, and (if it adds tables) its
sql.  we don't try to separate commands from library code.  the module
that first introduces a concept owns it (eg importer owns activities)
and later commands use its library files.  the only rule is that
nothing but the top level dispatcher imports a command (that's not
enforced by the language, but is checked by a test).  tests mirror the
source tree.

## display

i imagine graphical display of data having two layers.  first layer
would be associated with a command and would generate output in a
suitable format (eg sgv or some mapping data format) suitable for
display by third parties.  this layer would write output to a standard
directory which would also serve as cache (file names might be named
after command invocation to aid detecting when cached results can be
used).  second layer would be a simple local web server that (1)
interprets the URL after "localhost" as a nimchoo command and (2)
displays the result of executing that command.  this could involve
generating an intermediate html file that would similarly be cached.

this approach, with a lightweight server that simply invokes commands
and displays results is just a rough sketch - i haven't worked
through the details yet.

## activity selection

i can imagine that often it's useful (eg for a map) to select data
according to certain criteria.  one solution is to develop a mini
language that is shared by many commands.  another is a selection task
that generates a list of "ids" given those criteria that other tasks
then take as input.  yet another is to have a scratchpad in the
database that is the "current selection".  currently i think i prefer
the last solution (obvs this scratchpad is defined by a command that
itself uses the mini language, but that language is not shared by many
commands).

NOTE: this conflicts with the caching in display because it adds
implicit state.  we might work around this by including a hash of the
select in names as necessary.

## the database: fragments (migrations)

the structure of the database is described by sql files, "fragments", not
made by hand.  when `nch` opens a database it makes sure the file matches
what the program expects, by running any fragments the database has not
had yet.

* each module with tables keeps its sql in its own directory, as
  `NNN-name.sql` (eg `climbs/001-schema.sql`).  the module's `ddl.nim`
  lists them in order (`fragment("001-schema.sql")`); `src/nimchoo/modules.nim`
  joins the lists of all modules into `allFragments`.  the order of modules
  there matters: a module whose tables refer to another's comes after it.
  the sql is read at compile time, so it is inside the `nch` binary.
  `db/001-schema.sql` (the `user` table and spatialite's metadata) is
  applied first, always.  the numbers only order the files within a module.
* the database has a table `fragment` (name, applied_at, sha256 of the
  sql, seed_version).  on opening, for each fragment in the program: not
  recorded -> run its sql and record it, in one transaction; recorded with
  the same checksum -> nothing.  so a new database gets every fragment, an
  up to date one nothing, an old one only what was added since.
* two refusals: a recorded fragment whose checksum differs from the
  program's ("made by a different version of nch"), and a recorded
  fragment the program does not have ("from a newer version").  the
  messages say to `nch empty --all -f` (start again).
* so: **never edit a fragment that any database has had, and never delete
  one.**  to change a table, add a new numbered file (`alter table`,
  `update`, ...).  watch for sqlite limits: it cannot drop a column that
  has a foreign key, or one that an index uses, without rebuilding the
  table.  fragments are plain ddl; data is inserted from nim (a fragment
  may have a seed, `withSeed`, used by no module now).
* tests build their databases from scratch, so they do not care how many
  fragments there are; `tests/db/test_store.nim` lists the fragment names
  and counts them, and must be updated whenever a fragment is added or removed.

### squashing (decided 2026-11-05)

while only the author has a database we may, at a milestone, **squash**:
merge each module's fragments into its `001-schema.sql` (the final
schema), delete the later files and any retired module, and rebuild the
database (`nch empty --all -f`, then import again).  the cache survives
(downloads, settings), so nothing is fetched again.  rules:

* **once anyone else has a database, never squash again**: append only.
* before deleting the old fragments, compare the schema they make with the
  squashed one (every table, column, index and foreign key, from a fresh
  database each way), and keep a copy of the old database file until the
  author is happy with the new one.
* what a rebuild loses that cannot be made again from the fit files: the
  users and their fthr, models, the saved selection, the landmarks, and names
  given by hand (`nch sector --edit`).  the author chose to start from zero
  at the first squash; a save-and-restore of those few tables is a possible
  one-off script if it is ever wanted.
* the first squash (2026-11-05) removed: the `places` module (the embedded
  list of towns, `place` table, `activity.place_id`), `name_source`,
  `sector.kind`, `sector.name_checked`, and the one-off "forget the names"
  steps.

### other decisions to remember (details in TODO.md)

* names (climbs, activities, starts) come from GeoNames files downloaded on
  demand, read by one-degree cells into `feature`/`coverage`; every feature is
  kept and the rules choose.  a name is decided in the run that needs it, or the
  command stops with the reason (`DownloadError`); `--offline` answers
  "nothing" everywhere (names stay "" for good).  do not build lazy
  back-filling for a bad connection: need the internet and say so.
* tests must never use the network or the real cache: every `Globals` in a
  test says `offline: true`.
* landmarks (`nch landmark`) are the author's own names for places, shared
  by all users, and come before every other name.

## describing things: one standard way (decided 2026-11-05)

an activity and a climb are said the same way wherever they appear (the list, `nch climbs`, the sector
commands, messages), like `__str__` in python.  the one place that does it is `src/nimchoo/describe.nim`
(`activityLine` / `activityCells`, `climbLine` / `climbCells`, and the number formats).  a new command that
shows an activity or a climb uses it, and does not make its own format.

* an activity:  `2020-08-14 06:01  cycling  36.7km 1h41m  Providencia / Lo Barnechea and back`
  (start, sport, distance, active time, then the place it started and what it is called, joined by " / ").
  verbose adds the sub-sport (`cycling/road`) and, last, the path of the file.
* a climb:  `Cerro San Luis (4/5)  4 0.5km +89m 17.8%`  (name, category, length, gain, gradient).  in
  `nch climbs` the attempt follows:  `at 14.8km  9:41  24 of 34  best 8:25`.
* **no space between a number and its unit** (`36.7km`, `+89m`, `17.8%`, `1h41m`).
* in a table the parts are cells lined up in columns (padded, numbers to the right), headed `start`, `sport`,
  `distance`, `active`, `place / name` (and `path`); the one-line form is for headings and sentences.
* not recorded is `-` (dim); an activity with no positions says `no GPS` where the place and name would be (-v only).

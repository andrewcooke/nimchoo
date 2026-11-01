
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

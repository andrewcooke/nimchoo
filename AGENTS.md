
# nimchoo

this project is a reworking of choochoo (which can usually be found in
the choocho directory parallel to this one).  what i want to do is:

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

a few rules to guide behaviour:

* i will generally discuss a change before implementing it.  don't
  switch from discussion to implementation without my approval.

* while this account has sudo provileges you MUST NOT use sudo
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

as much as possible each "chunk" of funtionality should be
independent.  so, for example, it would be nice if each module that
extended data import had its own fragment of sql, ideally in a file
consisting only of ddl instructions, and the datbase as a whole is
made by applying these files in order.

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
through thd etails yet.


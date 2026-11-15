## Keys: short names for "what a view was made from", so that a frame can be kept while nothing it reads has changed.
##
## The rules (dev/display-arch/display-arch-crit-6.md):
## * a key is the SHA-256 of **named, length-prefixed parts in a fixed order**, so that two parts that are equal, or that run
##   together, cannot cancel or be mistaken for one another;
## * every frame key has the **identity of the database** (a key from one database never fits another), the **build** of the
##   program (a new build may make different frames), and the **name of the frame** (two frames made from the same data are
##   not the same key);
## * the data are keyed by **one counter per table** (`db/versions`): the key of a set of tables is made from their counters,
##   which a trigger increases on every insert, update and delete; a frame says which tables it reads;
## * the key of the **selection** is the subject's own (`Subject.selectionKey`), and is part of the key only if the frame reads
##   the selection.

import std/options
import ../db/[statement, versions]
import ../util/hashing/hashing
import ../util/version/version
import ../../core/errors

{.push raises: [].}

func keyOf*(parts: openArray[(string, string)]): string =
  ## The SHA-256 (hex) of the parts in the order given, each as `name`, the length of the value and the value, so that no
  ## two different lists of parts have the same text.
  var text = ""
  for (name, value) in parts:
    text.add name & ":" & $value.len & ":" & value & "\n"
  sha256Hex(text)

proc tablesKey*(db: DbConn, tables: seq[string]): string {.raises: [StoreError].} =
  ## The key of what is in these tables now: from their counters (a table is counted once, however it is listed).
  var parts: seq[(string, string)]
  for (name, version) in tableVersions(db, tables):
    parts.add (name, $version)
  keyOf(parts)

proc frameKey*(
    db: DbConn, frame: string, selection: Option[string], tables: seq[string]
): string {.raises: [StoreError].} =
  ## The key of a frame: `frame` is its full name ("map/activities/routes"), `selection` the subject's key of the
  ## selection if the frame reads it (none: it does not), `tables` those it reads.  The first 16 hex digits would do for
  ## a file name; the whole is returned.
  keyOf(
    [
      ("database", databaseIdentity(db)),
      ("build", nchBuild),
      ("frame", frame),
      ("selection", selection.get("(none)")),
      ("tables", tablesKey(db, tables)),
    ]
  )

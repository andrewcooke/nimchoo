## A condition for completing a name: the text in a column starts with what has been typed, whatever the case and
## accents (`fold`, which every connection has).  A piece of query, so the typed text is a bound value.

import std/strformat
import ./sqltext

{.push raises: [].}

func foldedPrefix*(column, typed: string): Sql =
  ## True for the rows where `column` starts with `typed`, folded alike.  It binds `:prefix`: one to a query.
  sqlFrom(fmt"substr(fold({column}), 1, length(fold(:prefix))) = fold(:prefix)", "db")
    .with("prefix", typed)

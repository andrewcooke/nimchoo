
i feel like we may have a latent pattern that it would be useful to
extract (keeping things in one place).  this is the handling of what
i'll called editable objects.  two examples are users and locations.
another, not yet fully developed, is ff models.

for all of these, we should probably:

* allow the user to list the existing objects and properties (perhaps
  with filtering?)

* allow the user to add, delete, and edit entries.

i guess we select these using --list --add --delete --edit?  maybe
--list is default if omitted?

editing can get quite complex.  i think each object has various
attributes (eg lat, lon for a location).  each attribute should be
asociated with a property on the command line.  for --list and
--delete they should be filetrs and take patterns/ranges.  for --edit
they take replacement values?  or do they select troo and we have a
different syntax for the replacement?

what do we do at the moment?  is teh above clear?  can you catalogue
what we currently have?  what do you suggest?


---

## The answer (discussed 2026-11-22)

### What exists (2026-11-22)

The shape was decided on 2026-11-05 (CLAUDE.md, "the shape of the commands"): `TYPE [which ones] [action]`, listing when no
action is given (so no `--list`), `--add NAME`, `--edit NAME ...`, `--delete`.  Each command implements it its own way:

| | list | filter the list | `--add` | `--edit` | `--delete` |
|---|---|---|---|---|---|
| `users` | yes | none | NAME + `--fthr`, `--default` | NAME + new values (`--fthr`, `--clear-fthr`, `--rename`, `--default`) | NAME |
| `landmarks` | yes | none of the landmarks (`--search`/`--near` search GeoNames for places to add) | NAME + where (`--at`, or a pick from a search) + `--size` | none | NAME |
| `models` | yes | none | NAME + 7 parameters | none (a model never changes) | none (waits for the `ff` rework) |
| `climbs` | yes | criteria (`--names`, `--from`, `--near`, `--categories` ...) | none (found from rides) | NAME + one change (`--rename`, `--auto`, `--retire`, `--unretire`) | `--all` only |
| `activities` | yes | criteria | none (imported) | none (`--rename` renames automatically) | by criteria |

Two families: **named things made by hand** (users, landmarks, models: few, edited by name; no filters; only `users` has
`--edit`) and **things found from data** (activities, climbs: many, selected by criteria, lightly editable).  The pattern
is the first family's.

### Decided

* **`--edit NAME` selects; the attribute options are the new values** (as `users` does now).  Filters are for listing and
  deleting.  Rejected: filters always, with a separate `--set attr=value` (bulk edits; a second syntax, and an edit that
  matches more than meant); and position deciding (filters before the action, values after: one option, two meanings).
* **Names are unique** within a type (the database says so: a unique index on the key), so the name is the one attribute
  that can only be set for one thing: setting it where the edit could reach a group is an error, said before anything is
  changed (the author, 2026-11-22).  With `--edit NAME` selecting exactly one thing this holds already; the rule matters
  if editing by selection is ever added, and the declaration marks the key attribute so that the shared code knows it.
* **`--delete` deletes the selection** given by the filters (as for activities), after the question (below) shows what
  it matched.
* **Activities and climbs stay as they are** (criteria, data-derived), sharing pieces: ranges, name patterns, `--from` /
  `--near` (`near`).
* **When:** with the `ff` rework.  First `landmarks` alone (it gains `--edit` and delete by selection), then `users`
  (which tests the hooks), then `models` as the third.  If the declaration has to bend for the second type, it is wrong.

### How it is built

A package of its own (say `editable`) holds the shared code; each type stays in its package and declares itself, and its
command is little more than a call with that declaration.  The declaration is the one fact everything is made from:

```nim
const landmarkKind* = Kind(
  noun: ("landmark", "landmarks"),
  table: "landmark", key: "name",
  attrs: @[
    Attr(name: "name",  kind: akText,     column: "name",   use: {shown, filter, required}),
    Attr(name: "size",  kind: akDistance, column: "size_m", use: {shown, filter, settable}, default: "200m"),
    Attr(name: "at",    kind: akPosition, column: "geom",   use: {shown, filter, settable, required}),
    Attr(name: "rides", kind: akCount,    sql: "(select count(*) ...)", use: {shown, filter}),  # worked out, never set
  ],
  check: landmarkCheck,      # rules beyond the kind: a size from 100m to 20km
  changed: nil,              # what follows a change (users: a new FTHR recalculates the impulses)
)
```

Made from it by the shared code:

* the **options and their help** (`util/args`), by kind: text takes name patterns, numbers, distances and durations take
  ranges with units (the reader of `--distance`), positions take `--near` with a place or `LAT,LON` (`near`);
* the **parse result**, a variant: `list(filters)`, `add(values)`, `edit(name, values)`, `delete(filters)`;
* the **SQL**: one `select` whose `where` is built from the filters as an `Sql` (values bound; column names from the
  declaration, never from input), `insert`, `update`, `delete` of the selection;
* the **table**: the shown attributes, each written by its kind (`km`, `interval`, the position writer), through `ruled`,
  ending with the list's done line;
* **tab completion**, from the option specs.

Kept by each type, as hooks in the declaration: `check` (rules beyond the kind), `changed` (what follows a change: one
default user; a new FTHR recalculates the impulses), and special ways to add (landmarks' `--search` / `--pick` from
GeoNames, an extra action beside the generated ones).

**The access model**: a statement is checked against the tables of the package it is written in, so shared code writing
the `user` table would be refused.  The declaration carries its owner and the shared code prepares its statements as that
package (`prepareStmtAs`): the owner declared the writing, so "a table is written by its owner" still holds.

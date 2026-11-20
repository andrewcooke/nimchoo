# part A: core, ui, util (status: done)

## findings (most important first)

### A1. A backtick in a value is taken as markup: the character is dropped and the rest is drawn in `code`
`src/nimchoo/core/theme.nim:388` (`Drawer.draw`), reached from `render` (`theme.nim:420`) and `Globals.inTheme` (`globals.nim:63`).
The backtick rule ("what is between backticks is `code`") is applied to the text of *every* span, values included.  The
`styled` macro promises "a value is plain text, whatever it holds" (`ui/markup.nim:116`), which holds for `<` `>` but not
for backticks.  Scenario: a GeoNames place name (they use `` ` `` for an ayn: "Jabal Umm `Adhbah"), an activity named from
it, or a path or a user-given name with one backtick, shown in colour: the backtick disappears and everything after it on
the line (in `g.say`: in the whole text, since one `Drawer` runs over all its lines) is in `code`.  Without colour it is
right, so tests (colour off) do not see it.
Fix: mark the spans whose backticks are markup (the literal pieces of `styled`/`g.say` text) and draw the others with
`typing = false`; or escape backticks in values.  Confidence: confirmed in the code; the data case plausible.

### A2. An option's arity is two facts: three booleans in `Opt`, an `Arity` enum in `OptDoc`, converted both ways
`src/nimchoo/packages/util/args/args.nim:63-68` (`takesValue`, `valueOptional`, `takesList`, and `apply`/`applyList`
either of which may be nil), `args.nim:214` (`doc` maps the booleans to `Arity`), `packages/activities/criteria.nim:242`
(maps `Arity` back to the booleans).  A bag of booleans with meaningless combinations (`takesList` and `valueOptional`;
`takesValue = false` with `valueOptional`; `takesList` with `applyList = nil` is a nil call at parse time), and the same
fact kept in step by hand in two places.  `custom(..., takes: bool, ...)` passes the bag on.
Fix: `Opt` holds `arity: Arity` (or a variant on it holding `apply` or `applyList`), and `doc` copies it.  Confidence:
confirmed.

### A3. `nch --config` works out the database's path and its source a second time
`src/nimchoo/settings.nim:155-162` and `:69-73` against `packages/db/store.nim:60` (`resolveDbPath`).  `configLines`
calls `resolveDbPath` for the path but decides "--db / $NCH_DB / the default" itself, and the environment table writes
the default as `getDataDir() / "nch" / "nch.db"` again.  If the rule changes in `store`, `--config` says the wrong
thing.  Likewise `settings.nim:194` lists the commands as the registry's `& @["packages"]` while `nch.nim:22`
(`allCommands`) is the real list (a third built-in command would be missing from `--config`).
Fix: `store` returns the path with where it came from (`(path, source)`), and `allCommands` moves where both can use it
(or is passed in).  Confidence: confirmed.

### A4. "done: N of TOTAL things" has no helper: two commands build it by hand, the others (and `nch packages`) do not end so
`src/nimchoo/packages/ui/vocabulary.nim:20` (`countSpan` gives only the number), `packages/activities/table.nim:180`
(builds the text with the count in it, then cuts the count off again by length: `text[count.len .. ^1]`),
`packages/climbs/command.nim:237` (builds " of " & `counted(...)` itself), `src/nimchoo/introspect.nim:236-240`.
The `ui` documentation makes it a rule ("The last line of a list is "done: N of TOTAL things""), but only activities and
climbs follow it; `nch packages` (a filtered list: `-U/-B/-T`), `nch users`, `nch landmarks` end without it, and
`nch packages` says "no package is kept by those filters" where the rule gives "done: 0 of 30 packages".  With no helper
that takes (n, total, one, many, selected, marks), each command has to rebuild it and most have not.
Fix: `vocabulary.listDone(n, total, one, many, selected, marks): Line` used by every list (and a test that a list command
ends with it).  Confidence: confirmed (activities, climbs, packages); users and landmarks by grep.

### A5. Markup read at run time is dead: `styled(paint, text)`, and with it the reason for `anyStyle`
`src/nimchoo/packages/ui/markup.nim:96` (`styled*(paint, text)`), `core/line.nim:61` (`anyStyle`: "for markup read
while the program runs").  Nothing in `src/`, `tests/` or `tools/` calls `styled(paint, ...)` or `parseMarkup` other
than the compile-time `styled` macro.  The module documentation still describes run-time markup ("Reading the markup
needs no theme, so it can be checked before a theme is known.  There is no fixed set of styles ...") which is no longer
how it is used: every style is checked against `programStyles` when compiled.
Fix: delete `styled(paint, text)`; make `parseMarkup` and `anyStyle` private to the macro's use; rewrite the module
doc.  Confidence: confirmed (grep).

### A6. `nch packages --help` and `inventory.nim` describe columns and views that are not there
`src/nimchoo/introspect.nim:162-166`, `src/nimchoo/core/inventory.nim:3`, `inventory.nim:125`.  The usage says the list
shows the packages "in dependency order, each with what it is for, its layer ..., how many packages it uses and is used
by, how many tables it owns, and what it provides".  `summaryLines` (`inventory.nim:196`) sorts by how many packages each
uses, then how many use it, and has three columns: package, U/B, what it is for; no layer, no count of tables, not
dependency order.  The module doc promises "trees, layers or a Graphviz graph": there is no Graphviz view and no layers
view.  `countOf` is unused (dead).  `introspect.nim:183-185` has an empty "--- the settings ---" section header (the
settings moved to `settings.nim`).
Fix: rewrite the intro from what `summaryLines` shows; drop "layers or a Graphviz graph"; delete `countOf` and the empty
header.  Confidence: confirmed.

### A7. The command list of every usage is lined up by hand (fixed 12 columns, not wrapped); the guard test cannot see it
`src/nimchoo/core/registry.nim:87-95` (`commandList`).  `" ".repeat(max(1, 12 - c.name.len)) & c.summary`: a two-column
table aligned by padding, with no wrapping to the width (a long summary runs past an 80-column terminal), while the `ui`
rule is that every table is `ruled` (or, like the options, laid out by `usage.nim` with a computed column and wrapping).
The guard, `tests/core/test_ruled.nim:56`, looks only for `align(`/`alignLeft(`, so padding with `repeat` passes.  The
doc comment says "each name in `cmd`": the style is `code` now.  It also sits oddly in `core/registry.nim` (the
dependency order), not with the usage code.
Fix: make the commands a section built by `usage.nim` (a `ruled` table, or the options' layout), move it there, and widen
the test to padding computed from a length.  Confidence: confirmed.

### A8. Who may read a table is worked out twice: `Access.readersOf` and `inventoryOf`
`src/nimchoo/core/access.nim:52` and `src/nimchoo/core/inventory.nim:108-113`.  `nch db` shows readers from
`access.readersOf`; `nch packages -T`/`nch packages NAME` from the inventory's own loop over `depends`.  They agree today;
if the access rule changes (say, reading through a dependency of a dependency, or a new shared owner), `nch packages`
will describe a rule that is no longer enforced.  `refusal` itself has a third statement of it (`access.nim:126-129`).
Fix: the inventory is made with the `Access` (it already has the fragments and depends) and asks `readersOf`.
Confidence: confirmed (duplication); no present disagreement found.

### A9. `Globals.width` and `Globals.colour` are half adopted: 53 calls ask the terminal again
`src/nimchoo/core/globals.nim:41-46`, `src/nch.nim:155-156`, `packages/ui/live.nim:146,182`.  `nch` fills
`g.width = [helpWidth(stdout), helpWidth(stderr)]` and `g.colour`, but only `tell` reads `g.width`; every usage and table
(53 calls: `usageError(g, "nch db", usageText(helpWidth(stderr)), ...)`, `helpWidth(stdout)` in the commands) asks
`helpWidth` itself, and `newTerminalLive(theme)` decides colour with `canColour()` instead of `g.colour[osErr]` (the
`paintOf(g, osErr)` that exists for this).  One fact read in two ways; and a test's `Globals` cannot set the width or
colour the command will use (they come from the real terminal), so wrapping and colour are only tested in pieces.
Fix: commands take the width from `g.width[o]` (perhaps a `g.usage(o, lines)` helper), and `newTerminalLive(g)` takes
`paintOf(g, osErr)`.  Confidence: confirmed (grep).

### A10. Sentinels where the rules want `Option` (in the core types everything uses)
`src/nimchoo/core/globals.nim:22-23` (`dbPath`, `user`: "" for the default), `nch.nim:52,151`
(`cacheDir().get("")` turns an `Option` into "" for `loadTheme`/`themeNames`, `themes/choose.nim:138`: "(""; none)"),
`core/logfile.nim:50` (`Log.problem`: "" if enabled; `nch.nim:196` tests `.len > 0`), `core/errors.nim:15-18,37,99,103`
(`offset` -1, `sheet` "", `row`/`line`/`column` 0 "if not known"), `util/args/args.nim:110` (`problem` returns "" if
nothing is wrong), `core/optdoc.nim:43` (`metavar` "" for a flag, a second statement of `arity == aFlag`),
`core/access.nim:111` (`caller` "": not checked).  CLAUDE.md: "ordinary absence is an `Option`.  no sentinel values";
`resolveDbPath(option: string)` and `settings.nim:158` then test `.len > 0`, so the "" convention spreads.
Fix: `Option[string]` for `dbPath`, `user`, the cache passed to the themes, and the error fields; `openLog` returns
`Result`-like `(Option[Log], Option[string])`; drop `Parsed.problem` (callers have `case parsed.kind`).  Confidence:
confirmed.

### A11. Two word-wrappers that measure differently: `wrap.wrap` counts bytes, `line.wrapped` counts characters
`src/nimchoo/core/wrap.nim:10-21` (`line.len`, `word.len`) against `core/line.nim:196` (`runeLen`).  Help, notes and
package documentation go through `wrap`/`prose`/`rst`; messages and table cells through `wrapped`.  Any non-ASCII text
wraps early in the first: `climbs/params.nim:173,250` (`farellones₂`, `Cabra₁`: 3 bytes each), accented names in
package docs (`fold`: "El Arrayán"), `…`.  `usage.label` also measures by bytes (`usage.nim:51`).  Two algorithms for
one job, already different in their result.
Fix: one wrapper (on `Line`, by characters); `prose`/`rst`/option help build `Line`s and use it.  Confidence:
confirmed (by reading; the effect is a line a column or two short).

### A12. `except Exception` for `moveFile`, written twice; a missing wrapper
`src/nimchoo/core/logfile.nim:107` (`rotate`) and `packages/util/atomic/atomic.nim:34` (`writeAtomic`).  CLAUDE.md:
never `except CatchableError`/`Exception` except at the top of a thread or server loop.  Both are there because
`moveFile` is inferred to raise anything; each handles it its own way (one discards, one converts to `OSError`), and
the next caller of `moveFile` will write a third.
Fix: one `moveFileOr(src, dst) {.raises: [OSError].}` in `util/atomic` (the one place that catches `Exception`, said
so), used by both.  Confidence: confirmed.

### A13. Stale references and dead bits (small, each confirmed)
* `core/errors.nim:5`: "See "Conventions" in TODO.md": the conventions are in CLAUDE.md.
* `packages/ui/units.nim:1`: "see AGENTS.md, "describing things"": no such section; the rules are in the `ui` doc.
* `packages/util/args/args.nim:292-294`: "Each kind comes twice: with the option's description ... and without
  (`documented` adds it afterwards: for the commands not yet converted)": there is no `documented`; each kind is once.
* `src/nch.nim:27`: `Head.offline` is never read (`--offline` sets `p.g.offline`).
* `nch.nim:121`: the synopsis `nch [--db PATH] [--user NAME] COMMAND [ARGS]` leaves out `--offline` and `--theme`.
* Three enums share the tag `ac` (`core/access.Action`: `acRead`; `completion.Action`: `acInstall`; `bundle`'s
  `acUnpack`), and two exported types are both called `Action`; the convention is a tag per type.
* `completion.nim:162`: `--install-completion` reports "wrote PATH: ..." with `g.say`, the path not in `file`, while
  `map`/`ff` show written paths in `file` (`map/command.nim:270`).
* `core/ownership.nim`: `tableEvents` and `parentTables` each parse `create [virtual] table [if not exists] NAME` with
  the same code (one helper would do).

## what is good

* The styled `Line` is the one currency of output: usages, tables, messages and live displays are all made of it, and
  `styleName`/`styled"..."` check style names when compiled; `programStyles` is one list that everything is made from.
* The message helpers (`failure`, `g.warn`, `g.done`, `usageError`) are small, in one place and used everywhere checked.
* Every module in this part has `{.push raises: [].}`; the parsers (theme, markup, template) raise typed errors with
  positions, and the `Parsed[T]` variant keeps a command's parameters valid by construction.
* `core` stays pure and below the packages (registry, access, ownership, inventory are all compile-time testable),
  and the registry's checks (cycles, names, points, foreign keys across packages) catch the package rules at build time.
* Tab completion is made from the same `OptDoc`s as the usage, so the two cannot drift (apart from A2).

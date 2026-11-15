# The review after step 3 (2026-11-14): a brief for a fresh session

`plan.md` asks for a review after step 3 (the largest step), in a fresh session, before steps 4 to 7: "each step can be right
while the whole drifts".  It gives no checklist; this is a draft of one, written by the assistant that did steps 0 to 3, which is
why the review is better done by another session (the one that wrote the plan, or a fresh one).

## The brief

Review the whole of nimchoo after steps 0 to 3 of the display plan (`dev/display-arch/plan.md`, the entries of `dev/HISTORY.md`
dated 2026-11-14; commits `17dbfba`, `4afaed9`, `3087f80`).  Read `CLAUDE.md`, `dev/display-arch/display-arch.md` and
`display-arch-crit-6.md` first.  Do not change code: report findings, ranked, with file and line, and propose what goes into
`TODO.md`.  Look for drift between the design and the code:

1. **The rules in `CLAUDE.md`**: one fact in one place, parse don't validate, delete dead code and stale docs, the `raises`
   discipline, `fmt` printing.
2. **Dependencies**: `nch packages --graph`.  Does `map` know nothing above it?  Do `activities` and `climbs` depend on `map` only
   for the frame types?  Are any `depends` lists too long or unused?
3. **Keys and counters**: are `frameKey` and `tablesKey` used anywhere yet?  Is there anything step 4 will trip on?  Is the
   triggers' trust model sound (the authorizer ignores trigger bodies; `db` makes triggers on every package's tables)?
4. **Frames**: does each declared `tables` list hold up on real data, not just the test fixtures (a recording, `db/access.nim`
   `startRecording`, against a copy of the author's database)?
5. **Tests**: do they mirror the packages?  Gaps: the web server's worker error paths, `ff` serving, the page script (only checked
   by hand with `tools/pagecheck.js`).
6. **Docs**: are the `##` package docs, help texts, `CLAUDE.md`, `TODO.md` and `README.md` consistent with what the code now
   does?  Grep the names removed in steps 1 to 3 (`--layers`, `--web`, `--state`, `--selection`, `proquint`, `bits`, `Layer`).
7. **What step 4 onwards will need** that is missing or awkward, and the departures from the plan listed at the end of the step 3
   entry in `dev/HISTORY.md`.

## Departures from the plan, for the reviewer to judge

* `Subject` gained `selected` and `emptyHint` (so a map can say "the selection of activities is empty").
* Tab completion of the subject is not done (the completion framework knows only options).
* The frames of a map are made one after the other in one process, not in one read transaction.
* A frame that fails fails the whole worker request; the page reports only a frame it cannot fetch.
* `nch map` serving only checks that the selection is not empty before it starts; the worker makes the files.
* The calendar's days with an activity are blue (step 1c removed the white/blue distinction).
* Step 2 does not need a database rebuild (HISTORY corrects the earlier statement).

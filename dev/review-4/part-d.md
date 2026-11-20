# part D: activities, names, selection, user (status: done)

(findings ranked most important first; written as confirmed.)

## 1. `users --edit` changes some things and then fails on the rest
`src/nimchoo/packages/user/command.nim:149-186`.  The FTHR and the default are written (and "bob: FTHR is 160" is
printed) before `--rename` checks that the new name is free; if it is taken the command fails with exit 1, leaving the
first changes made.  Scenario: `nch users --edit bob --fthr 160 --default --rename alice` with `alice` existing: bob's
FTHR and the default change, then "nch users: there is a user called 'alice' already".  (`--add` likewise does
`addUser`, `setDefaultUser`, `setFthr` as three statements, no transaction.)
*Fix:* check every precondition first and do the changes in one transaction (`st.begin`/`commit`), then say them.
*Confidence:* confirmed.

## 2. `landmarks --delete` does not follow the delete rule (no countdown, no `-f -f`, its own message)
`src/nimchoo/packages/names/params.nim:163` (`flag(Raw, ["-f", "--force"], force, ...)`, a `bool`) and
`src/nimchoo/packages/names/command.nim:96-108`.  CLAUDE.md: every `--delete` is confirmed with `-f`, with the countdown and
the "would delete ..." message, `-f -f` skipping the countdown.  Landmarks uses a plain bool flag (so `-f -f` is just
`-f`), never calls `pause()`, and without `-f` writes `g.say osErr, "would delete the landmark X: add `-f` to do it"`
instead of `failure(g, ..., "would delete X; use `-f` to confirm")` as activities and users do (different wording,
not in `bad`, no "nch landmarks:").  `confirm/confirm.nim:3` claims landmarks uses these helpers.
*Fix:* `forceOption(Raw, force, 1)` with a `Force` field, `failure(... "would delete ...")`, `pause(g.theme, what, force)`.
*Confidence:* confirmed.

## 3. `nch landmarks` breaks the option conventions: `--radius` in metres, `--near`/`--at` without place names
`src/nimchoo/packages/names/params.nim:96-157` (and `landmarks.nim:12-14`).  CLAUDE.md: "input never takes a unit for
distance (decimal km)"; `activities --radius KM` follows it, `landmarks --radius METRES` (100 to 20,000) does not, so the
same option name means different units in two commands.  CLAUDE.md also says `--from`, `--near`, `--at` "each also take a
place's name (a landmark, else the biggest place of that name)"; landmarks' `--near` and `--at` accept only `LAT,LON`
("`--near` is a position as LAT,LON in degrees").  `names/places.placeNamed` is in the same package and is not used.
In passing: "is `--radius` given?" is `raw.radiusM != defaultRadiusM` (`params.nim:230`), so `nch landmarks --radius 1000`
alone is accepted silently while `--radius 999` is refused; and `landmarks.problem()` returns `""` for "fine"
(`landmarks.nim:29-47`, a sentinel; parse, don't validate).
*Fix:* `--radius KM` (decimal km), `--near`/`--at LAT,LON|PLACE` through `placeNamed`, `radiusM: Option[float]` in `Raw`,
and a `LandmarkSpec` type that `problem` returns or refuses.
*Confidence:* confirmed.

## 4. "Nothing to do" is a success for `--delete` and a failure for `--rename`; notes lose their styles
`src/nimchoo/packages/activities/deleterun.nim:41-43` vs `activities/command.nim:466-478`.  With an empty selection,
`nch activities --delete` writes "nothing is selected: ..." plainly on stdout and exits 0 (`g.say osOut, nothing`);
`nch activities --rename` writes the same sentence through `failure()` on stderr, in `bad`, exit 1.  Same situation, two
answers.  In the same two branches the notes ("latest: ...", "starting near ...") are printed with
`g.say osOut, l.text & "\n"` (`command.nim:455,470`), while the listing shows the same `Line`s with `g.showAll`: the
styles are dropped and the line is not wrapped.
*Fix:* decide once (a `nothing` outcome said the same way by both, probably exit 0 on stdout) and print notes with
`g.showAll(osOut, m.notes)`.
*Confidence:* confirmed.

## 5. The "done:" line and list footers are not used by users, landmarks or `--rename`
`src/nimchoo/packages/user/command.nim:136-182`, `names/command.nim:112,151,153-170`, `activities/command.nim:415-421`.
The ui rules: what was done is `g.done()` ("done: ..."), and "the last line of a list is 'done: N of TOTAL things'".
`nch users --add/--edit` and `nch landmarks --add` say "made the user bob", "bob is now the default user", "made the
landmark X at ..." with `g.say osOut` (no "done:", no style for the count); `activities --rename` uses
`g.tell(osOut, plain("named 12 activities again ..."))`.  The lists of `nch users`, `nch landmarks` and the landmark
suggestions end without a count line, while `activities` and `climbs` end with `footerLine`/`countSpan`.  The consistency
pass reached `activities` and `climbs` but not these.
*Fix:* `g.done(...)` for every "made / renamed / named again" message, and a `doneLine(counted(n, ...))` under each of the
three lists.
*Confidence:* confirmed.

## 6. The listing's footer: counts by sport without commas, and "unknown" where the option says "none"
`src/nimchoo/packages/activities/table.nim:137-170`.  `text.add fmt"{v} {k}"` writes the count of each sport without
`count()`: with 1,113 cycling rides among several sports the footer says "(1113 cycling, 13 running)", against the ui rule
"a count has commas from 1,000" (and a test that refuses commas written elsewhere does not catch a missing one).  A
sport not recorded is counted as "unknown", while `--sports none` is how the user asks for it (and `resolve` turns an
empty sport into "none", `command.nim:211`).  Also `mapframes.nim:69` writes `{ids.len}` where line 63 uses `count(n)`.
*Fix:* `fmt"{count(v)} {k}"`, "none" for an unrecorded sport (one constant shared with `inValues`), `count(ids.len)`.
*Confidence:* confirmed.

## 7. `Criteria` is a bag of booleans and sentinels, checked afterwards
`src/nimchoo/packages/activities/criteria.nim:41-82, 591-627`; `command.nim:369-372`; `rows.nim:13-24,59-60`.
CLAUDE.md: "a command's `parseArgs` gives ... a variant on the action: a combination that means nothing cannot be
represented"; "no "" or -1 meaning none".  `Criteria` holds `all, given, select, delete, rename, force, verbose` as
independent fields and `finish()` refuses the bad combinations by hand (seven checks); `newest`/`oldest` use 0 for "no
limit" (and both may be set, refused later); `listActivities` returns `saved: -1` for "not asked"; `rowColumns` turns
NULL into `-1` and `''` in SQL and `readRows` turns them back (`if r.dist >= 0: some(...)`) though the query layer reads
`Option[float]` directly (it does so for `slat`/`slon` in the same tuple); `ListRow.sport` is "" for not recorded.  Users
and landmarks have variant `Params`; activities, the largest command, does not.  `hasFilter`, `refersTo` and
`withoutLatest` each list the criteria by hand, so a new criterion must be added in three places.
*Fix:* `Params = object case action: list(select: bool) | delete(force) | rename`, the criteria a separate object;
`limit: Option[(Newest|Oldest, int)]`; `saved: Option[int]`; read `Option` columns without the `coalesce(-1)`.
*Confidence:* confirmed (rule; previous reviews named sentinels in general, these remain).

## 8. Odd inputs accepted: `--all --radius`, and `--radius nan` / `inf`
`src/nimchoo/packages/activities/criteria.nim:361-372, 600-615`; `names/params.nim:144-152`, `names/landmarks.nim:45`.
`finish` refuses `--all` with a criterion before it turns `--radius` alone into `--from latest`, so `nch activities --all
--radius 5` is accepted (and lists or `--select`s the rides from near the latest start) while `--all --from latest` is
refused.  `parseFloat` reads "nan" and "inf": `--radius nan` passes `r <= 0` and gives NaN boxes (nothing found, no
message); `--radius inf` matches every activity.  In landmarks, `--add X --at 1,2 --radius nan` passes `problem()` (NaN
fails both comparisons) and reaches the insert, where SQLite's NULL fails `radius_m not null` with a raw SQLite message.
*Fix:* move the `--radius` default before the `--all` check; one reader of a positive finite number (`ui/units` or
`args`) used by both commands.
*Confidence:* confirmed by reading (not run).

## 9. The box round a circle is written three times, with three constants; one misses the date line
`src/nimchoo/packages/activities/criteria.nim:643-677` (`box`, `boxes`: 110.5 km a degree, a second box across 180°),
`names/suggest.nim:50-70` (`featuresAround`: 111,000 m, no wrap), `names/lookup.nim:44-66` (111,000 m, no wrap);
`activities/mapframes.nim:22` has 111,320 and `geo/cells.nim:83` its own `metresPerDegree`.  Scenario: `nch landmarks
--near -16.5,179.99` (Fiji) asks for east = 180.01 and finds nothing at -179.99.  A missing abstraction: `boxes` is pure
and already handles the poles and the date line.
*Fix:* move `box`/`boxes` (and one metres-a-degree) to `geo`, and use them in `suggest` and `lookup`.
*Confidence:* confirmed (the duplication); plausible (the Fiji case is rare in practice).

## 10. `ListRow.user` is dead, and costs a sub-query per row and a declared table
`src/nimchoo/packages/activities/rows.nim:21,62`, `table.nim:31`.  `rowColumns` computes `(select name from user where
id = f.user_id) as user` for every row; `ListRow.user` is written and never read anywhere (a listing is one user's since
the selection belongs to one user).  Because of it `calendarframe.nim:47` declares the table `user` among what the frame
reads.  `ListRow.file` is likewise only written.
*Fix:* drop the `user` (and `file`) columns and fields, and `"user"` from the frame's `tables`.
*Confidence:* confirmed (grep finds no reader).

## 11. `landmarkAt` searches the landmarks in a Nim loop, once per activity and per climb
`src/nimchoo/packages/names/landmarks.nim:82-89`, called from `names/activity.nim` (destination) and `names/climb.nim`.
It reads every landmark (`listLandmarks`, sorted by `fold(name)`) and measures each with `haversine` in Nim, for every
activity named and every climb.  CLAUDE.md: "spatial search are sql, not loops in nim".  (The `via` loop over landmarks
in `activity.nim` measures to the projected route and is the documented exception for features; this one is a plain
point-in-circle.)  The table has `lon`/`lat` reals, not a geometry, so it cannot use the spatial index either.
*Fix:* a `geom` point column and `select ... where ST_Distance(geom, MakePoint(:lon, :lat, 4326), 1) <= radius_m order
by 1 limit 1`.
*Confidence:* confirmed (rule); the cost is small while landmarks are few.

## 12. The user to work for is `""` when not given
`src/nimchoo/packages/user/session.nim:40-63`; read as `g.user.len > 0` in `user/command.nim:100` and
`names/command.nim:83`.  `openSession(path, fragments, user = "")`: `""` means "the default user", and the error text
branches on `user.len == 0`.  CLAUDE.md: "ordinary absence is an `Option`... no "" meaning none".  (`Globals.user` is
core's, but this package is its only reader.)  Also `wipe.findUser` repeats the lookup that `openSession` does, and
`users.exists` a third time (`command.nim:44`), each with its own error text.
*Fix:* `user: Option[string]` in `Globals` and `openSession`; one `findUser` (returning `Option[UserId]`) used by all three.
*Confidence:* confirmed.

## 13. Stale and multi-user leftovers in docs and signatures
* `subject/package.nim:1` and `subject/subjects.nim:1,5`: "activities, later climbs and FF statistics": climbs is a
  subject now (`climbs/subject.nim:24`).
* `confirm/package.nim:3-4` lists the deleting commands as activities, users, db, `climbs --all --delete`;
  `confirm.nim:3` says activities, climbs, users, landmarks, cache, db (and landmarks does not use it: finding 2).
* `activities/command.nim:93` "no activity of those users has the sport ..."; `criteria.nim:382` "(not the limits, the
  users or the display)"; `matchSql(userIds: seq[UserId], ...)` (`criteria.nim:815`) is always called with
  `@[st.userId]`: there is one user per command now.
* `activities/table.nim:5-8`: the example footer "2 activities, 108.2km, 5h03m" is no longer what is printed ("done: 2
  of 1,310 activities, ..."); `command.nim:2` lists "delete" among the commands.
* `user/wipe.nim:15` `userTables`, "the tables ... that emptying a user clears": nothing reads it but a test that
  checks it against the schema, i.e. a second list kept in step by hand; the deleting is by `on delete cascade`.  The
  module's name (`wipe`) no longer says what it holds (`describe`, `findUser`).
* `user/params.nim:140` writes the "not a name" text again
  although `notAName` exists for it (`params.nim:87`).
*Fix:* correct the texts; `matchSql(userId: UserId, ...)`; replace `userTables` by a test that every `user_id` column has
`on delete cascade`.
*Confidence:* confirmed.

## What is good
* `matchSql` is the one place criteria become SQL; every value bound by name, the offered criteria (`--climbs`) carry
  their package, and `--invert`'s NULL semantics are explicit and documented.
* The selection is small and right: `replaceSelection` is all-or-nothing, owned by `selection`, and the after-import hook
  keeps `importer` unaware of it.
* `subject` and the frames are clean extension points: activities contributes subject, routes, heat and calendar
  without the views knowing it.
* `users` has a variant `Params` (`FthrChange` keep/set/clear) and uses `confirm`'s `Force`, countdown and `sayDeleted`
  exactly as intended; `activities --delete` likewise.

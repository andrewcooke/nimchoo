# Fitness and fatigue: the rework (design note, started 2026-11-23)

The decision D5 of `dev/display-arch/plan.md` (step 7, "FF statistics"), and the author's list for the `ff` rework.  What is
decided is marked so; the rest is open.

## What the author wants (2026-11-23)

* Models with different parameters (done), and a model given as an existing one plus only the parameters that change.
* Some models built in.
* The training impulse worked out **for each activity**.
* Fitness and fatigue worked out accurately (below), unless the difference from what is done now is really small.
* Much more display: the impulse in the calendar; better plots.

## Decided

* **The model is the subject** (2026-11-23; of the three placings considered: FF as frames of the activities subject, the
  model as the subject, FF as a subject of its own).  The user selects models; the views show their curves (`plot`,
  `calendar`).
* **Fitness and fatigue never depend on the activity selection.**  A model may say which activities count, by tags
  (`sport:cycling*`: all cycling, nothing else), never by a choice of particular activities: its tag patterns are one of
  its parameters (an editable object, TODO 17).
* **`nch ff` manages the models** (2026-11-23): the plural command of the model, the subject (list, add, edit, delete,
  select), is `nch ff`, not `nch models`; the chart that `nch ff` draws now moves to `nch plot`.
* **A models selection, kept per user**, as the activities' and the climbs' (`--select`, `--also`, `--within`, the same
  steps), which the views show (a view's page is live and takes no list in its address, so it shows a kept selection).
  **Unlike those, models are there from the start and selected**: the built-in models exist, and a new user has them
  selected.
* **A model's parameters** (2026-11-23): `gamma`, `zero`, `one`, `max-gap`, `zones`, `fitness-decay`, `fatigue-decay`,
  and **its tag patterns** (which activities count), a parameter like the others.
* **A model is made from a base, by copying** (2026-11-23): `nch ff --add cycling:hard --base default --gamma 2.5` fills in
  every parameter from the base, then those given, and stores the model complete; it keeps no tie to its base (a later
  change of the base changes nothing else).  A model can be edited (an editable object): its stored impulses are then
  dropped and worked out again, as when the FTHR changes.  Rejected for now: a live link to the base (cycles, deleting a
  base in use, impulses worked out again down the chain, a listing that says which values are inherited).
* **Models are chosen by name** (2026-11-23): a model's name is written as a tag is (letters, digits, `-`, `_`, `:`, a
  structure such as `cycling:hard` by convention) and matched as tags are (case and accents aside, `*` for anything), so
  views and commands select models with patterns of names.  The names are not tags: nothing connects a model called
  `cycling` with the tag `sport:cycling`.
* **The impulse is the activity's**, and follows the activity selection: impulse per day is a calendar frame of the
  activities subject; it can be a column of their lists.

## How it is worked out now, and the question

* The impulse is kept by the clock hour (UTC): each hour a ride covers gets the impulse of its readings in that hour (table
  `impulse`).  The curves step by the hour, `y[h] = y[h-1] * exp(-1h/tau) + x[h]`, each hour's impulse a lump at its end;
  days are read off the hourly series.
* Proposed then: one impulse per activity, as a delta at one moment of it; measured below, and decided per stretch.

## Measured (2026-11-23, `tools/ffcompare.nim`: the author's 997 rides with heart rate, 3,830 day-ends, default model)

Against the impulse worked out by the minute (as good as exact), the largest and the mean difference of each day-end's value
(fatigue averages 311 and peaks at 1,523; fitness averages 1,886 and peaks at 4,063):

| method | fatigue: largest | fatigue: mean | fitness: largest | fitness: mean |
|---|---|---|---|---|
| by the hour (now) | 4.4 (0.29%) | 0.91 | 2.0 (0.05%) | 0.92 |
| one impulse an activity, at its start | 313 (21%) | 4.0 | 339 (8%) | 4.1 |
| one an activity, in its middle | 325 (21%) | 0.41 | 346 (9%) | 0.36 |
| one an activity, at its end | 21 (1.4%) | 3.5 | 22 (0.6%) | 3.5 |
| one an activity, at its centre (impulse-weighted) | 26 (1.7%) | 0.037 | 28 (0.7%) | 0.032 |
| **one a stretch of riding (`segment`), at its centre** | **0.10 (0.01%)** | **0.022** | **0.04 (0.00%)** | **0.017** |

The worst cases of one impulse an activity all come from one file (`2026-01-08-tyo.fit`: 25 minutes on 8 January, then 45
hours of nothing, then the ride on the 10th: TODO); a stretch is split where the riding stops, so it has none of them.
None of the author's rides is under way at midnight.

**Decided** (2026-11-23): the impulse is kept **per stretch**, at its impulse-weighted centre; an activity's impulse is the
sum of its stretches'; fitness and fatigue are exact sums of decaying lumps, at whatever times are wanted, on no grid; the
hourly table `impulse` goes.

## Open

* Which models are built in.
* The `plot` view and its frames (series), replacing `ff`'s own page (and E7, its dispatch, merged then); what `ff --file`
  becomes.
* The calendar frames: impulse per day (activities); fitness, fatigue, form (models).
* Form (fitness minus fatigue); hours or days; what `--fitness-scale`, `--fatigue-scale` and `--hourly` were for.
* Power estimates are a separate matter (where tags come in too, by the author: not FF).

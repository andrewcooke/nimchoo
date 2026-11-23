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
  (`sport:cycling*`: all cycling, nothing else), never by a choice of particular activities.  So a model's attributes are
  its parameters and its tag patterns (an editable object, TODO 17).
* **The impulse is the activity's**, and follows the activity selection: impulse per day is a calendar frame of the
  activities subject; it can be a column of their lists.

## How it is worked out now, and the question

* The impulse is kept by the clock hour (UTC): each hour a ride covers gets the impulse of its readings in that hour (table
  `impulse`).  The curves step by the hour, `y[h] = y[h-1] * exp(-1h/tau) + x[h]`, each hour's impulse a lump at its end;
  days are read off the hourly series.
* Proposed: one impulse per activity, as a delta at one moment of it (its start, middle or end: to choose); then a curve at
  any time is the sum over the activities before it of `impulse * exp(-(t - t_i)/tau)`, exact, on no grid (perhaps in SQL),
  and the hourly table goes.
* **First: measure** the difference between the two on the author's data, for every day of the history (fatigue, tau 7
  days, is the more sensitive), and decide by it.

## Open

* What selecting a model means (one selection of models per user, as the activities' and the climbs'?), and how a model
  "inherits" from another (a base model, and only what differs).
* Which models are built in.
* The `plot` view and its frames (series), replacing `ff`'s own page (and E7, its dispatch, merged then); what `ff --file`
  becomes.
* The calendar frames: impulse per day (activities); fitness, fatigue, form (models).
* Form (fitness minus fatigue); hours or days; what `--fitness-scale`, `--fatigue-scale` and `--hourly` were for.
* Power estimates are a separate matter (where tags come in too, by the author: not FF).


one feature we're missing right now is a plot of various details from
the selected activity(s).  these could include heart rate, altitude,
speed, temperature.

i am not sure all of these are recorded, and i suspect that even if
they are recorded, they belong to different packages, so i am unsure
exactly how this could work (i'd like them to be displayed together -
they share a common x axis).  maybe these are just additional frames
for activity?

there is one additional wrinkle - the x axis could be distance or
time.

and, mostly out of curiousity, how hard would it be to connect a plot
and a map so that moving the cursor on the plot moved a point on the
route ion the map?


---

## the design (discussed with the assistant, 2026-11-24 and 25)

a plot of one activity's channels against time or distance, the channels stacked in panels on a shared x axis.

1. **a new subject of the plot, `activity`** (beside `activities`; the name may confuse, but says what it is): the inside
   of one activity.  the frames of `activities` are per day and cannot share an axis with seconds.
2. **each channel is a frame, contributed by the package that owns its data**: altitude by the importer (stored, cleaned:
   `track.alt`: it belongs with the positions), and the fields of the records by **one package for all of them**
   (decided 2026-11-25; name open, say `channels`): heart rate (moved there: the `heartrate` package goes, the database
   is rebuilt), cadence, temperature, power, distance and speed.  one list of channels (name, FIT field, unit, storage,
   label) and everything made from it: one table, a row for each activity and channel `(activity_id, channel, t0, n, t,
   values)` (a new channel needs no new fragment), one import step, one codec, the frames.  why not a package each: they
   differ only in those attributes, so six near-identical packages (or thin ones round a library, the list spread over
   six places); the package model is for new behaviour, and `ff`'s use of heart rate stays its own package.  each channel
   has its own times (a sensor's dropouts handle themselves), stored as the gap from the reading before in LEB128 (measured
   2026-11-25: 4-byte offsets were two thirds of the channels' space, the channels sharing their times almost exactly;
   devices record every second or, Garmin's "smart recording", at gaps of 2 to 10 s, a byte a gap either way); the
   distance as the change from the reading before (zigzag, LEB128: about 2 bytes a reading).  a run of 1 s gaps written
   as one negative number (the author's idea) would save most of what is left of the times (about 6% of a database):
   not done, for a simpler format, and it can be added inside `series.nim`.
   **future hardware is not excluded**: a new package can keep its own table, import step (`importer/steps`) and frame
   (`plot/frames`), as `heartrate` does now; or, when one first wants it, the channels package defines a point
   (`channels/channels`) to which a package contributes one line of the list, and the channels package does the writing
   into its own table.  build neither now.
3. **distance and speed are the device's** (`distance`, `enhanced_speed`/`speed` in the records), computed from the cleaned
   positions only when a file has none.  there is no need to know whether they came from a wheel or the device's GPS (see
   the evidence below).
4. **every channel is optional for each activity**: files differ in what they record.  a panel with no data says so.
   cadence's unit follows the sport (rpm on a bike, steps a minute running).
5. **the x axis**: every frame gives `(t, value)` (other data refers to per-second data by time).  distance is one more
   series, d(t), and the page switches the x axis to distance by looking each t up in it, so no frame knows about
   distance.  distance is offered only when the activity has one.
6. **the plot changes in one way**: the span of the x axis is the subject's business (days for the subjects now, the
   activity's own extent for this one), not the plot's `--after`/`--before`.

7. **pauses are gaps on the time axis** (decided 2026-11-25: ugly but honest); on the distance axis they vanish by
   themselves.  which gaps: the import's kinds of break (step 1b); until then a line breaks where readings are more than
   15 s apart (`activityframes.pauseS`, a stopgap, gone with 1b).  not at the stretches: they join the pauses the device
   makes (for the climbs), so a 10-minute café stop was a straight line.
8. **several activities selected: chosen on the page** (decided 2026-11-25; the use: the selection holds every ride to
   Farellones, compare any two).  the page lists the selected activities (date and name), a box each, the newest ticked
   when it opens; the ticks are not remembered (which rides is meaningless once the selection changes).  ticked rides are
   overlaid, aligned at their starts (time since the start, or distance), a colour each, the legend giving the date.  a
   ride is loaded when it is ticked, as the map loads a frame (`?frame=NAME`, here with the activity's id: one value), so a
   large selection costs nothing until used.  **`--file` writes them all**: each frame's CSV holds every selected ride, a
   series each (about 14,400 rows a channel for a 4-hour ride: the help says so).  there is no option to choose rides
   (a `--pick N...` was discussed and dropped: it broke the rule that a list option has a plural name, needed numbers shown
   in `activities`, and could not reach the page without a list in its address or state stored beside the selection).

the accepted cost: distances on this plot differ by about a percent from those nch computes from routes (route lengths,
climbs, efforts).

**not now: the plot's cursor linked to the map.**  it is possible and not hard: every page comes from one server, so the
pages share an origin and `BroadcastChannel` lets them talk with no server work.  the plot would send the time under its
cursor, the map move a marker to the position at that time (which needs a frame with the full track and its times: the
routes are simplified and have none).  the reverse (route to plot) is more work: nearest track point, a rule drawn by hand
on the plot.

**open:**

* size: 4 hours is about 14,400 points a channel, fine for Observable Plot; thinning may be needed when overlaying.
* the list to tick holds the whole selection (1,094 rides after an import): left so for now (narrowing it is what
  `nch activities ... --select` is for); the newest N with a note is the alternative.

**order:**

0. **the column names, and a squash** (decided 2026-11-25; done 2026-11-25, dev/HISTORY.md).  an epoch time (Unix seconds) ends in `_epoch`; an offset or
   duration in `_s`; anything else is a word and its unit.  (the schema had `_t`, `_at`, `mtime` and short names for the
   same things.)

   | table | now | new |
   |---|---|---|
   | `file` | `imported_at` | `imported_epoch` |
   | `activity` | `start_t`, `end_t` | `start_epoch`, `end_epoch` |
   | `segment` | `start_t`, `end_t` | `start_epoch`, `end_epoch` |
   | `route_cell` | `t_in`, `t_out` | `in_epoch`, `out_epoch` |
   | `seen_file` | `mtime` | `modified_epoch` |
   | `track` | `t0`, `t1`, `n`, `t`, `lon`, `lat`, `alt` | `start_epoch`, `end_epoch`, `n_readings`, `offsets_s`, `lon_semi`, `lat_semi`, `alt_fit` |
   | `sector` | `found_at` | `found_epoch` |
   | `effort` | `start_t`, `finish_t` | `start_epoch`, `finish_epoch` (real: interpolated) |
   | `impulse` | `centre_t` | `centre_epoch` |
   | names' cells | `loaded_at` | `loaded_epoch` |
   | `ff_model` | `max_secs` | `max_gap_s` |
   | `fragment` | `applied_at` | `applied_epoch` |

   they stay: `elapsed_s`, `timer_s`, `utc_offset_s`, `start_m`, `size` (bytes), the `n` of `segment` and `impulse` (a
   stretch's number, not a count), `lon`/`lat` in degrees.  `heartrate_series` goes in step 1.  the Nim code's SQL changes
   with them (grep each old name); a test refuses a column ending in `_t` or `_at`.  squashed with the renames: the
   comparison of the old fragments' schema with the squashed one (the `db` package's rule) checks that only these names
   changed.  rebuild: `nch db --delete`, import.  also in this squash (from TODO.md, 2026-11-25): `activity.start` (a
   SpatiaLite `POINT`) becomes `start_point` (a point is written in full, as `geo/position` does; SpatiaLite registers a
   geometry column and its index by name, so a squash, not a fragment; `sector` keeps its name: it is for Strava-like
   segments to come); the stale comments of the climbs fragment ("(n/m) numbering", `nch sector --edit`, "or 005 by
   hand"); and `sector.name` null against '': kept (the author, 2026-11-25: null is "not looked at yet", '' is "looked, nothing to
   call it", two meanings each written one way; the rule against "" is against two ways of writing one meaning).  not in it: `sport` and `sub_sport` going (TODO.md).
1. the channels package, heart rate moved into it (`heartrate` goes).  done 2026-11-25 (dev/HISTORY.md).
1b. **the breaks of a ride, with their kind, stored at import** (decided 2026-11-25, revised the same day; done
   2026-11-25, dev/HISTORY.md).  one table, `ride_break(activity_id, start_epoch, end_epoch, kind)`, and each user breaks at the kinds it needs:

   | kind | what happened | climbs, the route | time plot | distance plot |
   |---|---|---|---|---|
   | `manual` | the rider stopped the timer (or the file does not say who) | break | break | break |
   | `carried` | auto-stopped, then too far or too fast: a car, a train | break | break | break |
   | `pause` | auto-stopped and the rider stayed within 30 m, however long; or auto-stopped in a ride with no positions (a trainer: nowhere to go) | — | break | — |
   | `error` | the GPS jumped 100 m or more and never came back (`splitAt`): no time is missing | break | — | — |

   (time and distance plots: nothing is missing in time at an `error`, and the device's distance ignores GPS faults.)  a
   blink (auto-stopped under 30 s while riding on at a bicycle's speed) is the device's noise: not stored, a line is
   drawn across it (the author).  the "empty bits" (timer pieces at the start or end of a ride holding no position: 414
   stretches under 10 s in the author's data, most the first) are dropped: no stretch, no break.  the riding's edges
   (the first timer start and the last stop, after `cover` and the empty bits) are two columns of `activity`
   (`riding_start_epoch`, `riding_end_epoch`; the session's own `start_epoch`, `end_epoch` stay).  the stretches (for the
   climbs, the impulses and the route's parts) are the riding minus its `manual`, `carried` and `error` breaks, made in
   one helper, and `segment` goes.  the existing code is kept and records instead of joining or cutting: `joinable` tells
   `manual`, `carried` and `pause` apart, `splitAt` finds the `error`s, `cover` tidies the edges.  the time plot breaks at
   `manual`, `carried` and `pause`, and `pauseS` goes.  the empty bits going and the trainer rides' pauses joining change
   some stretches and impulse rows on purpose: compare the efforts and impulses before and after, and look at what
   differs (a check, not a goal: "the same as before" is no reason).  why not `segment` plus a table of pauses (proposed
   and rejected): it stores one kind and leaves the others implicit.  rebuild: yes.
2. the `activity` subject with altitude and heart rate and the time axis.  done 2026-11-25 (dev/HISTORY.md): a plot frame
   says its axis (`axDays`, or `axActivity`: made for one activity, `&activity=ID` in the page's request); a subject may
   give its things one by one (`pick`: the selected rides, the newest first); `activities` makes the frames (altitude,
   and one for each channel of the list); the x axis is time from each ride's start (`h:mm`, ticks on round times) to the
   end of the longest ticked (no rescaling: the author); `--after`/`--before` are refused for it.
3. distance and speed (the axis and the frames).  done 2026-11-25 (dev/HISTORY.md): speed in km/h, distance in km
   (`activityframes.shownAs`); the distance is the device's, else along the positions within each stretch; a frame of one
   activity may grow along it (`PlotFrame.along`) and the page offers it as the x axis ("x: time, distance", remembered),
   placing each point by interpolating the distance at its time; on that axis every break is a gap of no width (the
   device's distance does not advance while the timer is off), so no rule of its own was needed.
4. cadence, temperature, power.

## the evidence for 3

**the files.**  55 of choochoo's test files (`../choochoo/data/test/source`: about 25 devices, Garmin Edge, Forerunner and
Fenix, Wahoo, Suunto, Zwift, an Apple Watch, Stryd), and 40 of the author's recent rides (an Edge 130 Plus with a speed
sensor):

* almost every device writes `distance` and speed in its records, with or without a speed sensor: they are a standard
  field, not something a wheel sensor adds.
* where there are no positions (a trainer, a foot pod, a watch indoors) the device's distance is the only one.
* devices ignore GPS spikes, with a wheel or without: the author's rides have jumps of 2011 m, 556 m and 473 m where the
  device's distance moved 0.1 m, 0 m and 7 m; an Edge 500 with no speed sensor, +41 m where it moved 6.5 m.  (this is
  the author's test: a spike that the device's distance follows proves it came from GPS; one it does not follow proves
  nothing either way.  many spikes happen while standing still, which is weaker evidence.)
* the list of sensors (`device_info`) is not reliable: many files have none even with power or cadence in the records.
* no channel can be assumed: heart rate, altitude, cadence, temperature and power each come and go by file (the author's
  older rides have cadence, the newer do not).
* the distance summed from the raw positions is longer than the device's: on the author's rides +0.3 to 1.5%, +3.7% and
  +8.7% on the two with the most spikes.

**why.**  distance from positions is hard: straight lines between fixes a second apart cut every curve (too short) and
jitter adds zigzags (too long), by amounts that depend on speed, road and GPS, so the error cannot be corrected.  a wheel
measures the path rolled; a device without one has the GPS chip's own speed (Doppler) and its accelerometer, which we do
not.  the device can filter its distance in real time (it only has to refuse an impossible step), but it cannot correct a
position: it would have to know where it really was, and its cleaning cannot look ahead, as ours does (a burst is dropped
only when a later position is reachable again).  so it records the fixes as the chip gave them (probably already smoothed
a little by the chip) and leaves the hindsight to others.  **how the firmware does this is inferred from the files, not
known.**

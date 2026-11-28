# A ride's altitude: the device's and a terrain model's, blended (the design, 2026-11-28)

Not started.  Each step is built only with the author's approval.

## Why

The map of climbs shows climbs in the flat part of Providencia (between latitudes -33.41686 and -33.43710 and
longitudes -70.61132 and -70.58467).  They are not there: they come from glitches in the device's altitude, which
`climbs/profile.nim` uses as it is, on the belief that a bike computer's altitude is barometric and clean.  It is not
(measured 2026-11-28, from `nch.db`):

* **The rides over a false climb do not climb.**  Each stored climb was found on one ride; the others that follow its
  route get efforts on it.  #47 Providencia₂ (stored 82 m, 20 %) has 173 efforts with a median net gain of **2 m**
  (from -39 m to +60 m); #150 Cerro San Luis₅ (106 m) 44 efforts, median 4 m.  Of the 105 climbs with three efforts or
  more, 12 have a median effort gain under half their stored gain; the worst 7 are all here.  Real climbs agree within
  a few metres (Cerro San Cristóbal₉: stored 225 m, efforts 230 m).
* **Two kinds of glitch.**  *Settling* at switch-on: ride 757's "climb" (#126, 237 m at 16 %) starts 6 s into the ride,
  the altitude rising from 364 m to 620 m in 4 minutes and then flat (with a step of 38 m in 7 s on the way).
  *Swings* in mid-ride: ride 556 falls 87 m in 18 s and comes back within about two minutes.
* **The level drifts between rides.**  The start of #47 reads from 437 m to 938 m over 304 rides; the plot of activities
  overlaid from their starts already shows lines hundreds of metres apart on the same road.
* The false climbs' stored gains sit just above the 80 m a climb needs: a glitch only has to be a little bigger than
  that to make one.

Confirming a climb by the other rides over it (proposed first) was rejected: often there are no other rides,
especially for a swing in mid-ride.  A terrain model was already on TODO.md.

## The terrain model on the false and the real climbs

The SRTM tile for Santiago (`S34W071`), interpolated bilinearly along each stored climb's route:

| climb | stored gain (device) | terrain: net gain | terrain: range |
|---|---|---|---|
| #47 Providencia₂ | 82 m | 3 m | 619–630 m |
| #150 Cerro San Luis₅ | 106 m | 5 m | 630–641 m |
| #126 near Providencia₃ | 237 m | 10 m | 615–632 m |
| #141 Cerro San Luis₄ | 81 m | 19 m | 626–655 m |
| #161 Cerro San Cristóbal₉ | 225 m | 228 m | 601–838 m |
| #181 Cerro San Cristóbal₁₁ | 181 m | 179 m | 640–829 m |
| #22 El Arrayán₁ | 81 m | 80 m | 876–959 m |

All 11 suspect climbs in the box are flat (1 to 19 m net); the real ones agree with the device.  The raw terrain is
noisy at small scales (the rises along San Cristóbal₉ add up to 506 m for 228 m of climb), so it is smoothed.

## Decisions

### 1. One altitude for a ride, used by everything

`nch plot activity` draws the altitude (`activities/activityframes.nim`, the frame `altitude`), today the device's.  If
climbs used another altitude, a climb could stand on a ride whose plotted line is flat.  So the question is **what a
ride's altitude is**, answered in one place (a package that owns it), and climbs and the plot both use it.  Nothing
else works altitude out.

### 2. The blend: the terrain above a scale, the device below it

Options considered: the terrain only (smoothed); a blend; a choice per ride (choochoo: the device shifted to the
terrain's level when the two agree, else the terrain: a threshold, and one swing condemns a ride).  **Chosen: the
blend** (the author's suggestion), a complementary filter over distance:

    altitude = device + smooth_σ(terrain − device)

Above σ it follows the terrain (the level, drift, settling, swings); below σ it keeps the barometer's detail (short
ramps, humps, a bridge rather than the river under it).  A ride without altitude (139 rides, 101 of them in 2019) is
the same formula without the device's term: the terrain smoothed by σ.  Every ride gets an altitude of the same kind
above σ.

Done over distance (resampled every 5 m, as `climbs/profile` does), within each stretch of riding (never across a
break).  Measured on the rides (net gain per effort, median [min..max], at most 40 rides a climb):

| climb, σ = 100 m | stored | device | terrain only | blend |
|---|---|---|---|---|
| #47 Providencia₂ (false) | 82 | 2 [−39..60] | 4 [2..5] | 4 [−1..14] |
| #150 Cerro San Luis₅ (false) | 106 | 2 [−39..24] | 6 [4..6] | 4 [−10..13] |
| #126 near Providencia₃ (false, settling) | 237 | 226 | 4 | 31 |
| #161 San Cristóbal₉ (real) | 225 | 230 [224..244] | 221 [216..223] | 228 [224..233] |
| #22 El Arrayán₁ (real) | 81 | 82 [70..89] | 79 [75..82] | 81 [72..84] |

* Swings go; real climbs keep their gain.
* **A step in the device's altitude is the weakness**: it leaves a blip about σ wide and up to the step's height.  #126
  falls from 226 m to 16 m (σ = 25 m), 22 m (50 m), 31 m (100 m): under the 80 m a climb needs, not gone.  No step
  detector unless the rebuilt catalogue shows a false climb made by one (then look at it, do not guess a threshold now).
* σ trades the terrain's noise against the device's faults: at σ = 25 m the rises along San Cristóbal₉ add up to 336 m
  for 226 m of climb; at 100 m, 242 m (the device: 231 m).
* Below about 100 m the barometer adds little to the climbs (blend and terrain differ by a few metres); the difference
  is in the plotted line.

**σ starts at 100 m** and is chosen properly in step 4: by the confirmed climbs (those whose efforts agree with their
stored gain: about 90, a reference for the gains) and by plotted rides for the author to look at (no ground truth for
the line).  It is a constant, not an option.

### 3. The source: AWS Terrain Tiles (SRTM), to be confirmed in step 1

* **Terrain Tiles** (`https://s3.amazonaws.com/elevation-tiles-prod/skadi/S34/S34W071.hgt.gz`, the registry of open
  data on AWS): SRTM at 1 arc-second (about 30 m), voids filled; no login; one tile a degree square, 3601 × 3601
  big-endian 16-bit metres (`S34W071` covers latitudes -34 to -33 and longitudes -71 to -70, row 0 at the north edge;
  -32768 is no height), gzipped (13 MB, 26 MB inflated: checked 2026-11-28, last changed 2016).  Read with zippy, which
  the program has.  SRTM is public domain; the tile set has an attribution list for some regions: **read it first**.
* Copernicus GLO-30 (also on AWS, no login, 42 MB a tile): newer, but a tiled compressed GeoTIFF (a TIFF reader by hand,
  or libtiff/GDAL, neither installed), a surface model that may include buildings in Providencia, and attribution.
  Measure it against the same climbs only if Terrain Tiles prove poor.
* NASA's own SRTM needs a login, which defeated choochoo's automation.

The author's rides start in about 3 tiles.

### 4. Stored: the raw terrain height of each position

The plot is live (made again on every request), so working out the terrain on demand would inflate a 26 MB tile per
request.  So the terrain height of each position of a track is stored, once, as an array (the encoding of `alt_fit`,
about 2 bytes a position, about 12 MB for the author's rides), filled at import (which already downloads place names)
and lazily otherwise, as the climbs are.  It is raw: the blend is done when the altitude is read, so σ can change
without rewriting anything.  The arrays are never changed once written.

Offline, or a tile that cannot be had: warn and leave the work undone (the ride has no terrain yet; its climbs wait),
never store a failure as a result.

## What changes for the author

* The climbs catalogue is rebuilt (`nch climbs --all --delete`, a new version of the method): numbers and names may
  change (no name is given by hand today); the false climbs go; gains and gradients are those of the blend; the rides
  without altitude get climbs.
* `nch plot activity` draws the blended altitude.
* A few tiles are downloaded once, about 13 MB each, kept in the cache (`data/terrain/`).

## Steps

1. **Licence and source.**  Read the Terrain Tiles attribution list; see what a tile over the sea gives (a 404,
   zeros?) and decide how a ride by the sea is handled; confirm the source with the author.
2. **A package that owns a ride's altitude** (`terrain`, or `altitude`): a `Source` in `download/sources.nim`; the tile
   of a position (the floor of latitude and longitude, `N`/`S`, `E`/`W`); a reader that refuses a file of the wrong
   size (an `NchError`) and reads -32768 as no height; `elevation(coord): Option[float]`, bilinear; its table of terrain
   heights per track, filled at import and lazily; the blend (one function: a ride's altitude, per stretch, over
   distance).  Tests on a small tile made by hand (edges, corners, the four hemispheres, missing heights) and on the
   blend (a step, a drift, a ride without altitude).
3. **Climbs and the plot on it.**  `climbs/profile.nim` takes the ride's altitude from the package; the `altitude`
   frame too.  A new version of the climbs' method; rebuild.
4. **Choose σ** (decision 2): the confirmed climbs' gains, before-and-after lists of the climbs, plotted rides.
5. **Text**: the top of `climbs/profile.nim` (its "barometric and clean"), the frame's summary ("from its positions,
   after cleaning"), the usage of `climbs` ("from the altitude"), NOTICE (the attribution), TODO.md, dev/HISTORY.md.

The measurements above were made with throwaway Python scripts reading `nch.db` and the tile (not kept).

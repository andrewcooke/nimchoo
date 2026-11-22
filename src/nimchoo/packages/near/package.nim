## `--from`, `--near` and `--radius`: where a thing is, for the commands that search by place.
##
## A position (`LAT,LON`, `geo/position`) or a place's name (a landmark, else the biggest place of that name among the names
## loaded: resolved by the command that runs, `names/places`), and, for `activities`, `latest` and `previous` (an activity found
## when the command runs).  `--from` is where a thing starts and `--near` is where its route or line passes; `--radius` is a
## distance with its unit, 10km round a start and 1km round a route unless it says, and it only goes with them (for
## `activities`, on its own it means `--from latest`).  The option specs, their help, the defaults and the reading are here
## (`near.nim`: `nearOptions`), so that `activities` and `climbs` cannot differ; `landmarks` reads its own `--near` and `--at`
## with the same `parseSpot`.

import ../../core/manifest

const package* = Package(depends: @["args", "geo", "ui"], fragments: @[])

## Flat geometry for rides, in metres.
##
## Positions come as longitude and latitude in degrees; for the distances and crossings here they are projected onto a flat
## plane round a reference point, which is accurate over the length of a ride.
##
## Also the **grid of cells** (`cells.nim`) that says where a ride went: latitude and longitude in cells of 1/1024 of a degree,
## each an integer (`(iy << 32) | ix`), with `coarsen` for the coarser levels and `reach` for how many cells a distance in
## metres is at a latitude.  One function for each, written here, is what SQL uses too (`db/functions.nim`).

import ../../core/manifest

const package* = Package(depends: @[], fragments: @[])

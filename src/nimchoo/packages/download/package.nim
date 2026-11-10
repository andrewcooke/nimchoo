## Fetching what the program needs from the network, the only place it does so.
##
## Everything it downloads is listed in `sources` (where from, what the file is, how big it may be).  Downloads are checked
## (size, free space, the zip inflated in a child) and announced as events, which go to the log and to the screen (a line
## that turns while the program waits).  Tests never use the network: every `Globals` in a test says `offline: true`.

import ../../core/manifest

const package* = Package(depends: @["atomic", "lookup", "ui", "zip"], fragments: @[])

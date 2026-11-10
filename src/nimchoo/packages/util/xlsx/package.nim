## A minimal xlsx reader: the cell values of worksheets, as strings.
##
## An xlsx file is a zip of XML files; this reads just enough of them (shared strings, relationships, cells) to load the FIT
## profile.  Its input is checked against what the standard library's XML parser cannot take (character references that are
## not characters: Nim issue 26681), and it is fuzzed (HISTORY.md).

import ../../../core/manifest

const package* = Package(depends: @["zip", "lookup"], fragments: @[])

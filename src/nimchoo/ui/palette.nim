## The colours of nch: five, named here and nowhere else.  Everything else says "green" or "grey",
## never a terminal code or a hex value, so a palette (even one for another background) is a change
## to this file alone.
##
## The terminal forms are escape codes (white is the terminal's own text colour, grey is its
## "dim"); the web forms are hex values for pages with a white background.

{.push raises: [].}

type Color* = enum
  white     ## ordinary text
  grey      ## quiet: bookkeeping, nothing to see, not recorded
  red       ## bad: failed, deleted, denied
  green     ## good: imported, saved, fitness
  yellow    ## a warning, and what is selected (some terminals draw it as orange)

func terminalCode*(c: Color): string =
  ## The escape code that starts the colour in a terminal ("" for white: nothing to start).
  case c
  of white: ""
  of grey: "\e[2m"
  of red: "\e[31m"
  of green: "\e[32m"
  of yellow: "\e[33m"

const resetCode* = "\e[0m"      ## ... and the one that ends any colour

func hex*(c: Color): string =
  ## The colour on a web page with a white background.
  case c
  of white: "#222222"
  of grey: "#868e96"
  of red: "#e03131"
  of green: "#2f9e44"
  of yellow: "#f08c00"

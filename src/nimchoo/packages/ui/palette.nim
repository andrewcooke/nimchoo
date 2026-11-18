## The colours of the web pages, named here and nowhere else: hex values for pages with a white background, given to the
## templates as tags (`{{blue}}`).  (The terminal's are the theme's: `core/theme.nim`; the pages will take theirs from the
## theme too: TODO "Styles, themes and markup", step 5.)

{.push raises: [].}

type Color* = enum
  white ## ordinary text
  grey ## quiet: bookkeeping, nothing to see, not recorded
  red ## bad: failed, deleted, denied
  green ## good: imported, saved, fitness
  yellow ## a warning (some terminals draw it as orange)
  blue ## what is selected (a light blue)

func hex*(c: Color): string =
  ## The colour on a web page with a white background.
  case c
  of white: "#222222"
  of grey: "#585858"
  of red: "#e03131"
  of green: "#2f9e44"
  of yellow: "#f08c00"
  of blue: "#4dabf7"

## The built-in themes (`dark.theme`, `light.theme`, beside this file), which define every style the program uses (a test
## checks); and, for the modules that draw, what draws a styled line (`core/line.nim`, `core/theme.render`,
## `core/globals.show`), all in one import.

import ../../core/[globals, line, theme]
export theme, line, globals.show, globals.showAll, globals.paintOf

{.push raises: [].}

const builtInThemes* = [
  (name: "dark", text: staticRead("dark.theme")),
  (name: "light", text: staticRead("light.theme")),
] ## the themes the program carries (the `themes` package unpacks them)

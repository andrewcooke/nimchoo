## Fitness and fatigue curves from the training impulses.
##
## `nch ff` adds up the hourly impulses of the user (`model`), each effort fading away exponentially, into one row per day (or
## hour) of fitness and fatigue, as CSV in the cache for plotting elsewhere or on standard output; `--web` serves a page that
## draws it (Observable Plot and d3, loaded from a CDN with the integrity hashes of the exact files).  `ff` is not about the
## selection: it always uses all the activities, and its `--check` is a hash of the data the curves are made from.  Offers its
## page to the server (`web/pages`).

import ../../core/[extension, manifest]
import ../web/request
import ./[command, web]

proc contributions(): seq[Contribution] {.nimcall, raises: [].} =
  @[contribute(webPage, ffPage(command.commandName))]

const package* = Package(
  depends: @[
    "args", "atomic", "bundle", "cache", "db", "model", "templating", "ui", "web",
    "importer", "user",
  ],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "the fitness and fatigue curves, as CSV for plotting",
      run: command.run,
    )
  ],
  contributes: contributions,
)

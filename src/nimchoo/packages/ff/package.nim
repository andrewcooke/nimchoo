## Fitness and fatigue curves from the training impulses.
##
## `nch ff` adds up the hourly impulses of the user (`model`), each effort fading away exponentially, into one row per day (or
## hour) of fitness and fatigue, and serves a page that draws it in the browser (Observable Plot and d3, loaded from a CDN with
## the integrity hashes of the exact files); `--file` makes the data as CSV in the cache for plotting elsewhere, and `--stdout`
## prints it.  `ff` is not about the selection: it always uses all the activities.  A chart is a live view: made again from the
## data as they are every time the page is asked for, in a file named by the options (`ff-default-hourly.csv`).  Offers its
## page to the server (`web/pages`).

import ../../core/[extension, manifest]
import ../web/request
import ./[command, params]

proc contributions(): seq[Contribution] {.nimcall, raises: [].} =
  @[contribute(webPage, pageOf(command.commandName, ffSpec()))]

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
      options: command.options,
    )
  ],
  contributes: contributions,
)

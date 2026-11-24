## A subject over time: `nch plot`, the view that draws the series packages contribute (`plot/frames`).
##
## `nch plot [SUBJECT]` serves a page that draws the frames of a subject, each a set of series over time that the package
## managing the subject contributes (`frames.nim`): the fitness, fatigue and form of the selected models (`nch plot ff`),
## the impulse of the selected activities each day (`nch plot`), and the altitude and channels of a selected ride over its
## own time (`nch plot activity`: frames over the time of one activity, which the page ticks and overlays from their
## starts).  The page is live (each frame made again whenever it is shown) and draws with Observable Plot, a panel a frame;
## `--file` makes a CSV file a frame and says the latest values.  The span of time (`--after`, `--before`, for frames over
## days) may be in the page's address.  Offers its page to the server (`web/pages`); the
## web options are done as every view does them (`web/view`).

import ../../core/[extension, manifest]
import ../web/request
import ../subject/subjects
import ./[command, frames, params]

proc contributions(): seq[Contribution] {.nimcall, raises: [].} =
  @[contribute(webPage, pageOf(command.commandName, plotSpec(), isWord))]

const package* = Package(
  depends:
    @["args", "atomic", "bundle", "cache", "subject", "templating", "ui", "user", "web"],
  commands: @[
    CommandDecl(
      name: command.commandName,
      summary: "a subject (by default the selected activities) over time",
      run: command.run,
      options: command.options,
    )
  ],
  defines: @[
    PointDecl(
      name: plotFramePoint.name,
      summary:
        "the frames of a plot, contributed by the packages that manage a subject: series over time, drawn as lines or bars",
    )
  ],
  contributes: contributions,
)

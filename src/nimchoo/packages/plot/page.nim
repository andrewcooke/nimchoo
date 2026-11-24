## The web page that shows a plot: Observable Plot and d3 (from a CDN, with the integrity hashes of the exact files, so a
## changed file is refused by the browser) drawing the frames of a subject, each a CSV file that the server gives it, in a
## panel of its own.  The page is a template (`page.html`, built in and kept in the cache's `system/templates/` as
## `plot.html`, see bundle/unpack.nim, where the author can change it) filled in with the title, the list of the frames
## (each with what it is, its unit, how it is drawn and whether it is ticked at first), the axis they share and, for frames
## of one activity, the things to tick (each with its number, start and label), and the libraries.  The page knows no
## frame: it draws lines or bars, by what each frame says.

import std/[json, options, strutils]
import ../bundle/unpack
import ../web/libraries
import ../text/templating/templating
import ../subject/subjects
import ./frames

{.push raises: [].}

const templateBundle* =
  Bundle(name: "templates/plot.html", data: staticRead("page.html"))

func markName(m: Mark): string =
  case m
  of mkLine: "line"
  of mkBar: "bar"
  of mkRule: "rule"

func axisName(a: Axis): string =
  case a
  of axDays: "days"
  of axActivity: "activity"

func stylesJson(styles: seq[RuleStyle]): JsonNode =
  result = newJArray()
  for s in styles:
    result.add %*{
      "series": s.series,
      "colour": s.colour,
      "band": s.band,
      "fadeToS": (if s.fadeToS.isSome: %s.fadeToS.get else: newJNull()),
      "alone": s.alone,
    }

func scriptText(j: JsonNode): string =
  ## JSON to put in a script: the page ends at the first "</script".
  ($j).replace("</", "<\\/")

proc renderPage*(
    source: string,
    libs: seq[(string, Value)],
    listed: seq[PlotFrame],
    axis: Axis,
    picks: seq[Pick],
    title: string,
): string {.raises: [TemplateError].} =
  ## The page from a template text, the libraries, the frames, their axis and the things to tick.  Pure.
  var list = newJArray()
  for f in listed:
    list.add %*{
      "name": f.name,
      "summary": f.summary,
      "shown": f.shown,
      "unit": f.unit,
      "mark": markName(f.mark),
      "along": f.axis == axActivity and f.along,
      "styles": stylesJson(f.styles),
    }
  var things = newJArray()
  for p in picks:
    things.add %*{"id": p.id, "start": p.start, "label": p.label}
  render(
    source,
    context(
      libs &
        @[
          ("title", text(title)),
          ("frames", text(scriptText(list))),
          ("axis", text(axisName(axis))),
          ("picks", text(scriptText(things))),
        ]
    ),
  )

proc pageHtml*(
    listed: seq[PlotFrame], axis: Axis, picks: seq[Pick], title: string
): string {.raises: [TemplateError].} =
  ## The page of a subject: every frame of it (`listed`, those that are `shown` ticked at first, all over `axis`) and the
  ## things to tick (`picks`, for frames of one activity), from the template and the libraries in use (the author's if they
  ## have put their own in the cache's `system/` part).
  renderPage(resolve(templateBundle).data, libraryValues(), listed, axis, picks, title)

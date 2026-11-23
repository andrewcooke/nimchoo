## The web page that shows a plot: Observable Plot and d3 (from a CDN, with the integrity hashes of the exact files, so a
## changed file is refused by the browser) drawing the frames of a subject, each a CSV file that the server gives it, in a
## panel of its own.  The page is a template (`page.html`, built in and kept in the cache's `system/templates/` as
## `plot.html`, see bundle/unpack.nim, where the author can change it) filled in with the title, the list of the frames
## (each with what it is, its unit, how it is drawn and whether it is ticked at first) and the libraries.  The page knows
## no frame: it draws lines or bars, by what each frame says.

import std/[json, strutils]
import ../bundle/unpack
import ../web/libraries
import ../text/templating/templating
import ./frames

{.push raises: [].}

const templateBundle* =
  Bundle(name: "templates/plot.html", data: staticRead("page.html"))

func markName(m: Mark): string =
  case m
  of mkLine: "line"
  of mkBar: "bar"

proc renderPage*(
    source: string, libs: seq[(string, Value)], listed: seq[PlotFrame], title: string
): string {.raises: [TemplateError].} =
  ## The page from a template text, the libraries and the frames.  Pure.
  var list = newJArray()
  for f in listed:
    list.add %*{
      "name": f.name,
      "summary": f.summary,
      "shown": f.shown,
      "unit": f.unit,
      "mark": markName(f.mark),
    }
  render(
    source,
    context(
      libs &
        @[
          ("title", text(title)),
          ("frames", text(($list).replace("</", "<\\/"))),
            # (in a script: the page ends at the first "</script")
        ]
    ),
  )

proc pageHtml*(
    listed: seq[PlotFrame], title: string
): string {.raises: [TemplateError].} =
  ## The page of a subject: every frame of it (`listed`, those that are `shown` ticked at first), from the template and the
  ## libraries in use (the author's if they have put their own in the cache's `system/` part).
  renderPage(resolve(templateBundle).data, libraryValues(), listed, title)

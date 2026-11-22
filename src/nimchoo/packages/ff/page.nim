## The web page that draws the fitness and fatigue of a CSV file (command.nim makes the file):
## Observable Plot and d3 (from a CDN, with the integrity hashes of the exact files, so a changed
## file is refused by the browser) drawing the two curves of a CSV that the server gives it.  The
## page is a template (page.html, built in and kept in the cache's `system/templates/`, see
## bundle/unpack.nim) filled in with the title, the name of the data, whether the rows are hours
## and the libraries (serve/libraries.nim); the colours of the two curves are in the template.
##
## Days are drawn as dates (the labels are dates of the computer's timezone, so they must not
## be shifted by the browser: the axis is in UTC); hours are instants and are drawn in the
## browser's timezone, which is the computer's.

import std/strutils
import ../bundle/unpack
import ../cache/cache
import ../web/libraries
import ../text/templating/templating

{.push raises: [].}

const pageTemplate* = staticRead("page.html")
const templateBundle* = Bundle(name: "templates/ff.html", data: pageTemplate)

proc renderPage*(
    source: string, libs: seq[(string, Value)], dataName, title: string, hourly: bool
): string {.raises: [TemplateError].} =
  ## The page from a template text and the libraries.  `dataName` is a CSV file of the cache directory (which is what makes
  ## it safe to put in the page): the name is made by `ff` itself, so one that is not is a bug.  Pure.
  doAssert isCacheFileName(dataName) and dataName.endsWith(".csv"),
    "the data of a page is a CSV of the cache directory: " & dataName
  render(
    source,
    context(
      libs &
        @[("title", text(title)), ("data", text(dataName)), ("hourly", flag(hourly))]
    ),
  )

proc pageHtml*(
    dataName, title: string, hourly: bool
): string {.raises: [TemplateError].} =
  ## The page for the CSV file `dataName`, from the template and the libraries in use (the author's
  ## if they have put their own in the cache's `system/` part).
  renderPage(resolve(templateBundle).data, libraryValues(), dataName, title, hourly)

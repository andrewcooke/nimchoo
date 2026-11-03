## The web page that draws the fitness and fatigue of a CSV file (command.nim makes the file):
## Observable Plot and d3 (from a CDN, with the integrity hashes of the exact files, so a
## changed file is refused by the browser) drawing the two curves of a CSV that the server
## gives it.  Pure: it returns the text.
##
## Days are drawn as dates (the labels are dates of the computer's timezone, so they must not
## be shifted by the browser: the axis is in UTC); hours are instants and are drawn in the
## browser's timezone, which is the computer's.

import std/[options, strutils]
import ../cache
import ../serve/pages

{.push raises: [].}

const
  d3Version* = "7.9.0"
  d3Hash* = "sha256-8glLv2FBs1lyLE/kVOtsSw8OQswQzHr5IfwVj864ZTk="
  plotVersion* = "0.6.17"
  plotHash* = "sha256-Q1gIZGd0B3fdeI1rJ6lc69uu/dUMcwowYBFwc71xNMs="
  d3Url = "https://unpkg.com/d3@" & d3Version & "/dist/d3.min.js"
  plotUrl = "https://unpkg.com/@observablehq/plot@" & plotVersion & "/dist/plot.umd.min.js"

const template1 = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>@TITLE@</title>
<style>
  body { margin: 16px; font: 14px system-ui, sans-serif; color: #222; }
  h1 { font-size: 15px; font-weight: 600; margin: 0 0 8px; }
  #note { color: #666; }
</style>
</head>
<body>
<h1>@TITLE@</h1>
<div id="chart"><span id="note">loading ...</span></div>
<script src="@D3@" integrity="@D3HASH@" crossorigin=""></script>
<script src="@PLOT@" integrity="@PLOTHASH@" crossorigin=""></script>
<script>
  const hourly = @HOURLY@;
  const chart = document.getElementById('chart');
  let long = [];
  function draw() {
    const plot = Plot.plot({
      width: Math.max(300, window.innerWidth - 32),
      height: Math.max(240, window.innerHeight - 90),
      x: { type: hourly ? 'time' : 'utc', label: null },
      y: { grid: true, label: null },
      color: { legend: true, domain: ['fitness', 'fatigue'], range: ['#2b6cb0', '#d1495b'] },
      marks: [
        Plot.ruleY([0]),
        Plot.lineY(long, { x: 'time', y: 'value', stroke: 'series', strokeWidth: 1.5 }),
        Plot.tip(long, Plot.pointerX({ x: 'time', y: 'value', stroke: 'series' }))
      ]
    });
    chart.replaceChildren(plot);
  }
  fetch('/files/@DATA@')
    .then((r) => { if (!r.ok) throw new Error('HTTP ' + r.status); return r.text(); })
    .then((text) => {
      // (csvParseRows, not csvParse: with a row function that one evals code, which the
      // page's content-security policy forbids)
      const rows = d3.csvParseRows(text).slice(1).map((d) => ({
        time: hourly ? new Date(d[0]) : new Date(d[0] + 'T00:00:00Z'),
        fitness: +d[1], fatigue: +d[2] }));
      long = rows.flatMap((r) => [
        { time: r.time, series: 'fitness', value: r.fitness },
        { time: r.time, series: 'fatigue', value: r.fatigue }]);
      draw();
      window.addEventListener('resize', draw);
    })
    .catch((e) => { document.getElementById('note').textContent = 'could not load the data: ' + e; });
</script>
</body>
</html>
"""

func pageHtml*(dataName, title: string, hourly: bool): Option[string] =
  ## The page for the CSV file `dataName` (a name of the cache directory, which is what makes
  ## it safe to put in the page).  None if the name is not one.
  if not isCacheFileName(dataName) or not dataName.endsWith(".csv"):
    return none(string)
  some(template1.fill({"TITLE": htmlEscape(title), "D3": d3Url, "D3HASH": d3Hash, "PLOT": plotUrl,
                       "PLOTHASH": plotHash, "HOURLY": if hourly: "true" else: "false", "DATA": dataName}))

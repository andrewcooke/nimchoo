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
import ../ui/palette

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
  h1 { font-size: 15px; font-weight: 600; margin: 0 0 4px; }
  #info { color: #666; margin: 0 0 8px; }
  .key { display: inline-block; width: 10px; height: 10px; margin: 0 4px 0 12px; border-radius: 2px; }
  #chart svg { touch-action: none; user-select: none; cursor: crosshair; }
</style>
</head>
<body>
<h1>@TITLE@</h1>
<div id="info"><span id="note">loading ...</span></div>
<div id="chart"></div>
<script src="@D3@" integrity="@D3HASH@" crossorigin=""></script>
<script src="@PLOT@" integrity="@PLOTHASH@" crossorigin=""></script>
<script>
  const hourly = @HOURLY@;
  const colours = { fitness: '@GREEN@', fatigue: '@RED@' };   // green and red, as in the terminal
  const chart = document.getElementById('chart');
  const info = document.getElementById('info');
  let long = [];          // every point: { time, series, value }
  let zoom = null;        // [from, to] (Dates) after a drag, else null: everything

  function describe() {
    const key = (name) => '<span class="key" style="background:' + colours[name] + '"></span>' + name;
    info.innerHTML = key('fitness') + key('fatigue') + '<span style="margin-left:16px">' +
      (zoom ? 'double-click to zoom out' : 'drag to zoom') + '</span>';
  }

  function draw() {
    const data = zoom ? long.filter((d) => d.time >= zoom[0] && d.time <= zoom[1]) : long;
    const plot = Plot.plot({
      width: Math.max(300, window.innerWidth - 32),
      height: Math.max(240, window.innerHeight - 90),
      x: { type: hourly ? 'time' : 'utc', label: null, domain: zoom || undefined },
      y: { grid: true, label: null },
      color: { domain: ['fitness', 'fatigue'], range: [colours.fitness, colours.fatigue] },
      marks: [
        Plot.lineY(data, { x: 'time', y: 'value', stroke: 'series', strokeWidth: 1.5 }),
        Plot.tip(data, Plot.pointerX({ x: 'time', y: 'value', stroke: 'series' }))
      ]
    });
    chart.replaceChildren(plot);
    describe();
    brush(plot);
  }

  // Drag across the chart to zoom to that span; double-click to go back.  (Plot draws, it does
  // not zoom: the chart is drawn again with the dragged span as its time axis.)
  function brush(plot) {
    const scale = plot.scale('x');
    const [d0, d1] = scale.domain.map((d) => +d);
    const [r0, r1] = scale.range;
    const timeAt = (px) => new Date(d0 + (px - r0) / (r1 - r0) * (d1 - d0));
    const px = (e) => e.clientX - plot.getBoundingClientRect().left;
    let from = null, box = null;
    plot.addEventListener('pointerdown', (e) => {
      if (e.button !== 0) return;
      from = Math.min(Math.max(px(e), r0), r1);
      box = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
      box.setAttribute('y', 0);
      box.setAttribute('height', plot.getBoundingClientRect().height);
      box.setAttribute('fill', 'rgba(0, 0, 0, 0.08)');
      box.setAttribute('x', from);
      box.setAttribute('width', 0);
      plot.appendChild(box);
      plot.setPointerCapture(e.pointerId);
    });
    plot.addEventListener('pointermove', (e) => {
      if (from === null) return;
      const to = Math.min(Math.max(px(e), r0), r1);
      box.setAttribute('x', Math.min(from, to));
      box.setAttribute('width', Math.abs(to - from));
    });
    plot.addEventListener('pointerup', (e) => {
      if (from === null) return;
      const to = Math.min(Math.max(px(e), r0), r1);
      const start = from;
      from = null;
      box.remove();
      if (Math.abs(to - start) < 6) return;                 // a click, not a drag
      zoom = [timeAt(Math.min(start, to)), timeAt(Math.max(start, to))];
      draw();
    });
    plot.addEventListener('dblclick', () => { zoom = null; draw(); });
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
    .catch((e) => { info.textContent = 'could not load the data: ' + e; });
</script>
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
                       "PLOTHASH": plotHash, "GREEN": hex(green), "RED": hex(red), "HOURLY": if hourly: "true" else: "false", "DATA": dataName}))

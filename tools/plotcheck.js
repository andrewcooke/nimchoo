// Runs the page of `nch plot activity` (its script, with the real d3 7.9.0 and Observable Plot 0.6.17) in node with a stand-in
// DOM (jsdom), answering its requests for frames from the CSV files given, and prints what it drew: the panels, the
// colour of each line, the x axis.  Then it ticks the second activity (the colours already there must not change), and
// chooses the distance as the x axis.  Not part of `nimble test` (it needs packages that the project does not carry):
//
//     d=$(mktemp -d); (cd $d && npm i jsdom@24 d3@7.9.0 @observablehq/plot@0.6.17)
//     page=$(nch plot activity --worker)      # and, for the two newest activities (their ids are in the page):
//     nch plot activity --worker --frame altitude --activity ID ...  (altitude, heartrate, distance)
//     NODE_PATH=$d/node_modules node tools/plotcheck.js $page $(dirname $page)/plot-activity-*-ID*.csv
//
// (a request for `?frame=NAME&activity=ID` is given the file `plot-activity-NAME-ID.csv`.)
const fs = require('fs');
const path = require('path');
const { JSDOM } = require('jsdom');
const [, , htmlPath, ...csvPaths] = process.argv;
const html = fs.readFileSync(htmlPath, 'utf8').replace(/<script[^>]*src="[^"]*"[^>]*><\/script>/g, '');
const files = new Map(csvPaths.map((p) => [path.basename(p), fs.readFileSync(p, 'utf8')]));
const dom = new JSDOM(html, { runScripts: 'outside-only', pretendToBeVisual: true, url: 'http://localhost/plot/activity' });
const w = dom.window;
w.innerWidth = 1000;
w.innerHeight = 800;
const fetched = [];
w.fetch = (url) => {
  const q = new URL(url, 'http://localhost/').searchParams;
  const name = 'plot-activity-' + q.get('frame') + (q.get('activity') ? '-' + q.get('activity') : '') + '.csv';
  fetched.push(name);
  const body = files.get(name);
  return Promise.resolve({ ok: body !== undefined, status: body === undefined ? 404 : 200, text: () => Promise.resolve(body) });
};
const modules = (process.env.NODE_PATH || '').split(':')[0];
for (const lib of ['d3/dist/d3.min.js', '@observablehq/plot/dist/plot.umd.min.js'])
  w.eval(fs.readFileSync(path.join(modules, lib), 'utf8'));
w.eval([...w.document.querySelectorAll('script')].map((s) => s.textContent).join('\n'));

const texts = (selector, root = w.document) => [...root.querySelectorAll(selector)].map((e) => e.textContent.trim());
function report(when) {
  console.log(when + ': "' + w.document.getElementById('info').textContent + '"');
  for (const p of w.document.querySelectorAll('.panel')) {
    const strokes = [...p.querySelectorAll('svg [aria-label="line"] path')].map((e) => e.getAttribute('stroke') || e.parentNode.getAttribute('stroke'));
    const ticks = texts('[aria-label="x-axis tick label"] text', p);
    console.log('  ' + p.querySelector('h2').textContent.split(' (')[0] + ': lines ' + JSON.stringify(strokes) + '; x ' + ticks[0] + ' ... ' + ticks[ticks.length - 1]);
  }
}
const later = (ms) => new Promise((done) => setTimeout(done, ms));
(async () => {
  await later(1500);
  report('at first');
  console.log('frames to tick: ' + texts('#frames label').join(', ') + '; x: ' + texts('#axis label').join(', '));
  const boxes = w.document.querySelectorAll('#picks input');
  boxes[1].checked = true;
  boxes[1].dispatchEvent(new w.Event('change'));
  await later(1500);
  report('the second ticked (the first keeps its colour)');
  const radios = w.document.querySelectorAll('#axis input');
  radios[1].checked = true;
  radios[1].dispatchEvent(new w.Event('change'));
  await later(1500);
  report('x: ' + texts('#axis label')[1]);
  console.log('fetched: ' + fetched.join(', '));
})();

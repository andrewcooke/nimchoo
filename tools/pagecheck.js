// Runs the page of `nch map` (its script and the frames' drawings, with the real Leaflet 1.9.4) in node with a stand-in DOM (jsdom),
// against the GeoJSON files of its frames, and prints the text the page puts in its caption ("could not draw the map: ..." and the stack if it fails).  The pixels are not drawn
// (the canvas is a stub), but the logic of Leaflet is: this found that a layer added straight to the map before it has a view makes the
// canvas renderer early and the layer groups added before it fail ("can't access property min").  Not part of `nimble test` (it
// needs packages that the project does not carry):
//
//     d=$(mktemp -d); (cd $d && npm i jsdom@24 leaflet@1.9.4)
//     NODE_PATH=$d/node_modules node tools/pagecheck.js $(nch map --frames routes climbs efforts gates heat --worker)
//
// (the worker prints the page, then the file of each frame; the page's fetch of `/files/NAME` is given the file of that name)
const fs = require('fs');
const { JSDOM } = require('jsdom');
const path = require('path');
const [,, htmlPath, ...geoPaths] = process.argv;
let html = fs.readFileSync(htmlPath, 'utf8');
const geo = new Map(geoPaths.map((p) => [path.basename(p), fs.readFileSync(p, 'utf8')]));
html = html.replace(/<script[^>]*src="[^"]*"[^>]*><\/script>/g, '').replace(/<link[^>]*>/g, '');
const dom = new JSDOM(html, { runScripts: 'outside-only', pretendToBeVisual: true, url: 'http://localhost/' });
const w = dom.window;
for (const p of ['clientWidth', 'offsetWidth']) Object.defineProperty(w.HTMLElement.prototype, p, { get() { return 900; } });
for (const p of ['clientHeight', 'offsetHeight']) Object.defineProperty(w.HTMLElement.prototype, p, { get() { return 600; } });
const noop = new Proxy(function () {}, { get: (t, k) => (k === 'canvas' ? undefined : noop), apply: () => noop, set: () => true });
w.HTMLCanvasElement.prototype.getContext = () => noop;
w.fetch = (url) => {
  const name = url.replace('/files/', '');
  return Promise.resolve(geo.has(name) ? { ok: true, json: () => Promise.resolve(JSON.parse(geo.get(name))) } : { ok: false, status: 404 });
};
w.eval(fs.readFileSync(require.resolve('leaflet/dist/leaflet-src.js'), 'utf8'));
const scripts = [...dom.window.document.querySelectorAll('script')].map((s) => s.textContent).filter((t) => t.includes('L.map'));
let src = scripts[0].replace('const map = L.map(', 'const map = window.theMap = L.map(').replace("caption.textContent = 'could not draw the map: ' + e;", "caption.textContent = 'could not draw the map: ' + e; console.log('STACK', e.stack);");
w.eval(src);
setTimeout(() => {
  w.document.getElementById('map').dispatchEvent(new w.MouseEvent('mousemove', { clientX: 450, clientY: 300, bubbles: true }));
  console.log('CURSOR:', w.document.getElementById('cursor').textContent);
  const m = w.theMap, c = m.getCenter();
  console.log('VIEW:', c.lat.toFixed(5), c.lng.toFixed(5), 'zoom', m.getZoom());
  console.log('CAPTION:', w.document.getElementById('caption').textContent); process.exit(0); }, 1500);

// Runs the page of `nch map` (its script, with the real Leaflet 1.9.4) in node with a stand-in DOM (jsdom), against a GeoJSON file, and
// prints the text the page puts in its caption ("could not load the routes: ..." and the stack if it fails).  The pixels are not drawn
// (the canvas is a stub), but the logic of Leaflet is: this found that a layer added straight to the map before it has a view makes the
// canvas renderer early and the layer groups added before it fail ("can't access property min").  Not part of `nimble test` (it
// needs packages that the project does not carry):
//
//     d=$(mktemp -d); (cd $d && npm i jsdom@24 leaflet@1.9.4)
//     page=$(nch map --selection t --layers routes,climbs,efforts,gates --worker | head -2)   # the page, then the data
//     NODE_PATH=$d/node_modules node tools/pagecheck.js $(echo "$page" | sed -n 1p) $(echo "$page" | sed -n 2p)
const fs = require('fs');
const { JSDOM } = require('jsdom');
const [,, htmlPath, geoPath] = process.argv;
let html = fs.readFileSync(htmlPath, 'utf8');
const geo = fs.readFileSync(geoPath, 'utf8');
html = html.replace(/<script[^>]*src="[^"]*"[^>]*><\/script>/g, '').replace(/<link[^>]*>/g, '');
const dom = new JSDOM(html, { runScripts: 'outside-only', pretendToBeVisual: true, url: 'http://localhost/' });
const w = dom.window;
for (const p of ['clientWidth', 'offsetWidth']) Object.defineProperty(w.HTMLElement.prototype, p, { get() { return 900; } });
for (const p of ['clientHeight', 'offsetHeight']) Object.defineProperty(w.HTMLElement.prototype, p, { get() { return 600; } });
const noop = new Proxy(function () {}, { get: (t, k) => (k === 'canvas' ? undefined : noop), apply: () => noop, set: () => true });
w.HTMLCanvasElement.prototype.getContext = () => noop;
w.fetch = () => Promise.resolve({ ok: true, json: () => Promise.resolve(JSON.parse(geo)) });
w.eval(fs.readFileSync(require.resolve('leaflet/dist/leaflet-src.js'), 'utf8'));
const scripts = [...dom.window.document.querySelectorAll('script')].map((s) => s.textContent).filter((t) => t.includes('L.map'));
let src = scripts[0].replace("caption.textContent = 'could not load the routes: ' + e;", "caption.textContent = 'could not load the routes: ' + e; console.log('STACK', e.stack);");
w.eval(src);
setTimeout(() => { console.log('CAPTION:', w.document.getElementById('caption').textContent); process.exit(0); }, 1500);

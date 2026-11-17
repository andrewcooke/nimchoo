// How the routes of activities are drawn on the map: a frame's drawing (see the map package, `map/frames.nim`), editable here in
// system/templates/ (delete it to have the built-in one again).  The numbers and colours are in activities-map-routes.json.
//
// Routes as threads: each route is moved a little to the side of its direction of travel, by an amount of its own, so that routes
// over the same road look like one line from far and like several threads from close.  The climbs are placed beside the
// outermost thread, so the spread is shared with them.
(features, ctx) => {
  const { L, helpers: h } = ctx, s = ctx.style;
  const spreadM = s.spread_m;                                     // the widest offset of a route, to either side, in metres
  ctx.shared.routesSpreadM = spreadM;

  // an offset in -1 .. 1 for route k of n: evenly spread over the width, in a scattered order (so the neighbours along the road
  // are not always neighbours in the cord)
  function laneOf(k, n) {
    const gcd = (a, b) => (b === 0 ? a : gcd(b, a % b));
    let step = Math.max(1, Math.round(n * 0.618));
    while (gcd(step, n) !== 1) step++;
    return (((k * step) % n) + 0.5) / n * 2 - 1;
  }

  // the lanes are given in the order of the activities' ids; the paths are moved in place, then smoothed
  const rounds = ctx.common.smooth_rounds;
  const routes = features.filter((f) => (f.properties || {}).kind === 'route').sort((a, b) => a.properties.id - b.properties.id);
  routes.forEach((f, k) => {
    const offsetM = laneOf(k, routes.length) * spreadM, g = f.geometry;
    if (g.type === 'LineString') g.coordinates = h.smoothPath(h.offsetPath(g.coordinates, offsetM), rounds);
    else if (g.type === 'MultiLineString') g.coordinates = g.coordinates.map((part) => h.smoothPath(h.offsetPath(part, offsetM), rounds));
  });
  const layer = L.geoJSON({ type: 'FeatureCollection', features: routes }, {
    style: { color: s.color, weight: s.weight, opacity: s.opacity },
    onEachFeature: (f, l) => {
      const p = f.properties || {};
      l.bindPopup(h.text(p.start || '') + '<br>' + h.text(p.sport || '') + ' ' +
                  (p.distance_m ? (p.distance_m / 1000).toFixed(1) + 'km' : ''));
    }
  });
  ctx.add(layer, 20);
  const n = routes.length;
  return {
    bounds: layer.getBounds(), rank: 1,
    caption: n ? n + ' routes' + (n > 1 && spreadM ? ' (each moved up to ' + spreadM + ' m to the side)' : '') : ''
  };
}

// How the climbs are drawn on the map: a frame's drawing (see the map package, `map/frames.nim`), editable here in
// system/templates/ (delete it to have the system standard again).  The numbers and colours are in activities-map-climbs.json.
//
// Transparent grey bands beside the road, marking sections of it, under the routes.  A band is a fixed width on the ground and a
// fixed distance beyond the outermost thread of the routes, in metres, so it is a band beside the road when zoomed in and all but
// disappears when zoomed out (its width in pixels is worked out again when the zoom changes).  Climbs on the same stretch of road
// go in different lanes so that they do not overlap: a climb takes the lowest lane that no climb on the same road (a longer one,
// placed first) has, and climbs that share no road share a lane.
(features, ctx) => {
  const { L, map, helpers: h } = ctx, s = ctx.style;
  const sameRoadM = 15;           // two climbs are on the same road if their points are this close
  const sameRoadLengthM = 60;     // ... along at least this length (so roads that merely cross are not the same road)

  // how far from the road (in metres, negative: to the right of the direction of travel) the middle of a lane is.  The lanes
  // alternate sides of the road: 0 to the right, 1 to the left, 2 further right, 3 further left ...  (no routes: no threads)
  const offsetM = (lane) =>
    (lane % 2 === 0 ? -1 : 1) * ((ctx.shared.routesSpreadM || 0) + s.gap_m + s.width_m / 2 + s.lane_m * Math.floor(lane / 2));

  // the points of a path every `stepM` metres along it, in metres from `origin` ([lon, lat]), with a grid to find the ones near
  // a point
  function roadOf(coordinates, origin, stepM) {
    const kx = h.metresPerDegree * Math.cos(origin[1] * Math.PI / 180), ky = h.metresPerDegree;
    const xy = coordinates.map((p) => [(p[0] - origin[0]) * kx, (p[1] - origin[1]) * ky]);
    const points = [xy[0]];
    let carried = 0;                                              // the distance along the path since the last point
    for (let i = 1; i < xy.length; i++) {
      const dx = xy[i][0] - xy[i - 1][0], dy = xy[i][1] - xy[i - 1][1], d = Math.hypot(dx, dy);
      let at = stepM - carried;
      for (; at <= d; at += stepM) points.push([xy[i - 1][0] + dx * at / d, xy[i - 1][1] + dy * at / d]);
      carried = d - (at - stepM);
    }
    const cells = new Map();
    const cellOf = (x, y) => Math.floor(x / sameRoadM) + ',' + Math.floor(y / sameRoadM);
    points.forEach((p) => { const k = cellOf(p[0], p[1]); if (!cells.has(k)) cells.set(k, []); cells.get(k).push(p); });
    const near = (p) => {
      const cx = Math.floor(p[0] / sameRoadM), cy = Math.floor(p[1] / sameRoadM);
      for (let dx = -1; dx <= 1; dx++) for (let dy = -1; dy <= 1; dy++)
        for (const q of cells.get((cx + dx) + ',' + (cy + dy)) || []) if (Math.hypot(p[0] - q[0], p[1] - q[1]) <= sameRoadM) return true;
      return false;
    };
    const xs = points.map((p) => p[0]), ys = points.map((p) => p[1]);
    const box = [Math.min(...xs) - sameRoadM, Math.min(...ys) - sameRoadM, Math.max(...xs) + sameRoadM, Math.max(...ys) + sameRoadM];
    return { points, near, box };
  }

  // the lane (0, 1, 2 ...) of each climb, by its id
  function lanesOf(climbs) {
    const sorted = climbs.slice().sort((a, b) => b.properties.length_m - a.properties.length_m || a.properties.id - b.properties.id);
    if (sorted.length === 0) return new Map();
    const origin = sorted[0].geometry.coordinates[0];
    const roads = sorted.map((f) => roadOf(f.geometry.coordinates, origin, sameRoadM));
    const boxesMeet = (a, b) => a[0] <= b[2] && b[0] <= a[2] && a[1] <= b[3] && b[1] <= a[3];
    const shares = (a, b) => {                                    // whether a runs along b for long enough
      let along = 0;
      for (const p of roads[a].points) if (roads[b].near(p) && (along += sameRoadM) >= sameRoadLengthM) return true;
      return false;
    };
    const lanes = new Map();
    sorted.forEach((f, i) => {
      const taken = new Set();
      for (let j = 0; j < i; j++)
        if (boxesMeet(roads[i].box, roads[j].box) && (shares(i, j) || shares(j, i)))
          taken.add(lanes.get(sorted[j].properties.id));
      let lane = 0;
      while (taken.has(lane)) lane++;
      lanes.set(f.properties.id, lane);
    });
    return lanes;
  }

  const climbs = features.filter((f) => (f.properties || {}).kind === 'climb');
  const lanes = lanesOf(climbs);
  const placed = [];
  const layer = L.geoJSON({ type: 'FeatureCollection', features: climbs }, {
    style: { color: s.color, weight: 1, opacity: s.opacity },
    onEachFeature: (f, l) => {
      const p = f.properties || {};
      const facts = (p.category ? 'category ' + h.text(p.category) + ', ' : '') + (p.length_m / 1000).toFixed(1) + 'km, +' +
                    Math.round(p.gain_m) + 'm, ' + p.gradient.toFixed(1) + '%';
      l.bindTooltip(h.text(p.name || ''), { sticky: true });
      l.bindPopup('<b>' + h.text(p.name || '') + '</b><br>' + facts);
      placed.push([f, f.geometry.coordinates, l]);
    }
  });
  ctx.add(layer, 10);
  // moved to their lanes the first time (when every frame is drawn, so the routes' spread is known), and made as wide in pixels as
  // their width in metres whenever the zoom changes
  let moved = false;
  const update = () => {
    if (!moved) {
      placed.forEach(([f, original, l]) => {
        const off = offsetM(lanes.get(f.properties.id));
        const road = h.simplifyPath(original, Math.abs(off) * 0.35);       // (so that hairpins do not make loops)
        l.setLatLngs(L.GeoJSON.coordsToLatLngs(h.smoothPath(h.offsetPath(road, off), ctx.common.smooth_rounds), 0));
      });
      moved = true;
    }
    const weight = s.width_m / h.metresPerPixel(map.getZoom(), map.getCenter().lat);
    placed.forEach(([f, original, l]) => l.setStyle({ weight }));
  };
  const m = climbs.length;
  return { bounds: layer.getBounds(), rank: 2, update, caption: m ? m + ' climbs (grey, beside the road, to either side)' : '' };
}

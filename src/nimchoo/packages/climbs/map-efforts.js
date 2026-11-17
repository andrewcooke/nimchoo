// How the efforts on the climbs are drawn on the map: a frame's drawing (see the map package, `map/frames.nim`), editable here in
// system/templates/ (delete it to have the built-in one again).  The numbers and colours are in activities-map-efforts.json.
//
// The part of each ride between the start and finish times stored for an effort on a climb, with a dot where it starts and where
// it finishes: for looking at how a climb is matched.  (The dots go in a group of their own, added after the lines: a layer added
// straight to the map before it has a view makes the canvas renderer early, and the groups added before it then find a renderer
// that is not set up yet.)
(features, ctx) => {
  const { L, helpers: h } = ctx, s = ctx.style;
  const efforts = features.filter((f) => (f.properties || {}).kind === 'effort');
  const dots = [];
  const layer = L.geoJSON({ type: 'FeatureCollection', features: efforts }, {
    style: { color: s.color, weight: s.weight, opacity: s.opacity },
    onEachFeature: (f, l) => {
      const p = f.properties || {}, c = f.geometry.coordinates;
      const facts = h.text(p.name || '') + '<br>' + h.text(p.start || '') + ' to ' + h.text(p.finish || '') + '<br>' +
                    Math.floor(p.elapsed_s / 60) + ' min ' + Math.round(p.elapsed_s % 60) + ' s; started ' + p.start_m +
                    ' m into the ride (activity ' + p.activity + ')';
      l.bindPopup(facts);
      if (c.length > 0) {
        const dot = (xy, colour, what) => dots.push(L.circleMarker([xy[1], xy[0]], { radius: s.radius, color: colour, fillColor: colour, fillOpacity: 1, weight: 1 })
                                                     .bindPopup(what + ' of the effort<br>' + facts));
        dot(c[0], s.start, 'start');
        dot(c[c.length - 1], s.finish, 'finish');
      }
    }
  });
  ctx.add(layer, 30);
  ctx.add(L.layerGroup(dots), 30);
  const n = efforts.length;
  return { bounds: layer.getBounds(), rank: 2, caption: n ? n + ' efforts (thick, a green dot where each starts and a red one where it finishes)' : '' };
}

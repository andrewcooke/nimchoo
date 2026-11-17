// How the gates of the climbs are drawn on the map: a frame's drawing (see the map package, `map/frames.nim`), editable here in
// system/templates/ (delete it to have the built-in one again).  The numbers and colours are in activities-map-gates.json.
//
// Short lines across the road, in the colour of the end they belong to: for looking at how a climb is matched (a ride shows where
// it crosses a gate; a switchback can make it cross twice).
(features, ctx) => {
  const { L, helpers: h } = ctx, s = ctx.style;
  const gates = features.filter((f) => (f.properties || {}).kind === 'gate');
  const layer = L.geoJSON({ type: 'FeatureCollection', features: gates }, {
    style: (f) => ({ color: f.properties.end === 'start' ? s.start : s.finish, weight: s.weight, opacity: s.opacity }),
    onEachFeature: (f, l) => l.bindPopup(h.text(f.properties.name || '') + '<br>' + f.properties.end + ' gate'),
  });
  ctx.add(layer, 40);
  return { bounds: layer.getBounds(), rank: 2, caption: gates.length ? gates.length / 2 + ' climbs with their gates (green: start, red: finish)' : '' };
}

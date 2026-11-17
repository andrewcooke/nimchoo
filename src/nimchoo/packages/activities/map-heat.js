// How the heat (how often each place was visited) is drawn on the map: a frame's drawing (see the map package, `map/frames.nim`),
// editable here in system/templates/ (delete it to have the built-in one again).  The numbers and colours are in
// activities-map-heat.json.
//
// Squares of the grid at several sizes (`level`; the file has each).  The size that suits the zoom is shown (the style says from
// which zoom), under everything else, coloured on a log scale so that a few busy places do not wash out the rest.
(features, ctx) => {
  const { L, map, helpers: h } = ctx, s = ctx.style;
  map.createPane('heat').style.zIndex = 350;
  const layers = new Map();
  const cellsOf = features.filter((f) => (f.properties || {}).kind === 'heat');
  for (const level of new Set(cellsOf.map((f) => f.properties.level))) {
    const cells = cellsOf.filter((f) => f.properties.level === level);
    const most = Math.max(...cells.map((f) => f.properties.visits));
    const at = (f) => Math.log(1 + f.properties.visits) / Math.log(1 + most);
    layers.set(level, L.geoJSON({ type: 'FeatureCollection', features: cells }, {
      pane: 'heat',
      style: (f) => ({ stroke: false, fillColor: h.mix(h.rgb(s.low), h.rgb(s.high), at(f)),
                       fillOpacity: s.opacity_low + (s.opacity_high - s.opacity_low) * at(f) }),
      onEachFeature: (f, l) => {
        const p = f.properties;
        l.bindPopup(p.rides + (p.rides === 1 ? ' ride' : ' rides') + ', ' + p.visits + (p.visits === 1 ? ' visit' : ' visits'));
      }
    }));
  }
  if (layers.size === 0) return {};
  let shown = null;
  const update = () => {                                          // the finest level the zoom allows (the coarsest if none)
    const zoom = map.getZoom();
    let level = null;
    for (const l of s.levels) if (layers.has(l.level) && zoom >= l.min_zoom && (level === null || l.level < level)) level = l.level;
    if (level === null) level = Math.max(...layers.keys());
    if (level === shown) return;
    if (shown !== null) map.removeLayer(layers.get(shown));
    layers.get(level).addTo(map);
    shown = level;
  };
  return {
    bounds: layers.get(Math.max(...layers.keys())).getBounds(), rank: 3, update,
    caption: 'heat: how often each place was visited (more is stronger; the cells grow as you zoom out)'
  };
}

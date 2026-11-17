// How the heat (how often each place was visited) is drawn on the map: a frame's drawing (see the map package, `map/frames.nim`),
// editable here in system/templates/ (delete it to have the built-in one again).  The numbers and colours are in
// activities-map-heat.json.
//
// A smooth glow (Leaflet.heat, which the page loads for this frame) from the cells of the grid at several sizes (`level`; the file
// has each): the size that suits the zoom is used, each cell a point at its middle, weighted on a log scale of its visits so that a
// few busy places do not wash out the rest, and spread over about `radius_cells` cells.  It is under everything else.
(features, ctx) => {
  const { L, map, helpers: h } = ctx, s = ctx.style;
  // (Leaflet.heat always puts its canvas in the overlay pane, where it would be drawn over the routes; this puts it in a pane of
  // its own, underneath, and back before the plugin takes it out)
  if (!map.getPane('heat')) map.createPane('heat').style.zIndex = 350;
  const Under = L.HeatLayer.extend({
    onAdd(m) { L.HeatLayer.prototype.onAdd.call(this, m); m.getPane('heat').appendChild(this._canvas); },
    onRemove(m) { m.getPanes().overlayPane.appendChild(this._canvas); L.HeatLayer.prototype.onRemove.call(this, m); },
  });
  const levels = new Map();                                       // level -> the points of its cells
  const cellsOf = features.filter((f) => (f.properties || {}).kind === 'heat');
  for (const level of new Set(cellsOf.map((f) => f.properties.level))) {
    const cells = cellsOf.filter((f) => f.properties.level === level);
    const most = Math.max(...cells.map((f) => f.properties.visits));
    levels.set(level, cells.map((f) => {
      const ring = f.geometry.coordinates[0];                   // a square: its middle is half way along the diagonal
      return [(ring[0][1] + ring[2][1]) / 2, (ring[0][0] + ring[2][0]) / 2, Math.log(1 + f.properties.visits) / Math.log(1 + most)];
    }));
  }
  if (levels.size === 0) return {};
  const heat = new Under([], { max: 1, minOpacity: s.min_opacity, gradient: { 0.0: s.low, 1.0: s.high } });
  ctx.add(heat, 0);
  let shown = null;
  const cellM = (level) => h.metresPerDegree / 1024 * Math.pow(2, level);   // the height of a cell of a level
  const update = () => {                                          // the finest level the zoom allows (the coarsest if none)
    const zoom = map.getZoom();
    let level = null;
    for (const l of s.levels) if (levels.has(l.level) && zoom >= l.min_zoom && (level === null || l.level < level)) level = l.level;
    if (level === null) level = Math.max(...levels.keys());
    const px = Math.max(4, s.radius_cells * cellM(level) / h.metresPerPixel(zoom, map.getCenter().lat));
    heat.setOptions({ radius: px, blur: px });
    if (level !== shown) { heat.setLatLngs(levels.get(level)); shown = level; }
  };
  const coarsest = levels.get(Math.max(...levels.keys()));
  return {
    bounds: L.latLngBounds(coarsest.map((p) => [p[0], p[1]])), rank: 3, update,
    caption: 'heat: how often each place was visited (stronger is more often)'
  };
}

## The web page that shows a heat map: Leaflet (from a CDN, with the integrity hashes of
## the exact files, so a changed file is refused by the browser) drawing the routes of a
## GeoJSON file that the server gives it.  Pure: it returns the text.
##
## The routes are drawn as thin, mostly transparent lines, so where many rides share a road
## the lines add up and glow.  A click on a line says which activity it is.

import std/[options, strutils]
import ../cache
import ../serve/pages

{.push raises: [].}

const
  leafletVersion* = "1.9.4"
  leafletJsHash* = "sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo="
  leafletCssHash* = "sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY="
  cdn = "https://unpkg.com/leaflet@" & leafletVersion & "/dist/"
  tiles = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"

const template1 = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>@TITLE@</title>
<link rel="stylesheet" href="@CDN@leaflet.css" integrity="@CSSHASH@" crossorigin="">
<style>
  html, body, #map { height: 100%; margin: 0; }
  #caption { position: absolute; z-index: 1000; left: 54px; top: 10px; padding: 4px 8px;
             background: rgba(255, 255, 255, 0.85); font: 13px sans-serif; border-radius: 3px; }
</style>
</head>
<body>
<div id="map"></div>
<div id="caption">loading the routes ...</div>
<script src="@CDN@leaflet.js" integrity="@JSHASH@" crossorigin=""></script>
<script>
  const caption = document.getElementById('caption');
  const map = L.map('map', { preferCanvas: true });
  L.tileLayer('@TILES@', {
    maxZoom: 19,
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
  }).addTo(map);
  const text = (s) => { const d = document.createElement('div'); d.textContent = s; return d.innerHTML; };
  fetch('/files/@DATA@')
    .then((r) => { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
    .then((data) => {
      const layer = L.geoJSON(data, {
        style: { color: '#c2185b', weight: 2, opacity: 0.25 },
        onEachFeature: (f, l) => {
          const p = f.properties || {};
          l.bindPopup(text(p.start || '') + '<br>' + text(p.sport || '') + ' ' +
                      (p.distance_m ? (p.distance_m / 1000).toFixed(1) + 'km' : ''));
        }
      }).addTo(map);
      const bounds = layer.getBounds();
      if (bounds.isValid()) map.fitBounds(bounds); else map.setView([0, 0], 2);
      caption.textContent = data.features.length + ' routes';
    })
    .catch((e) => { caption.textContent = 'could not load the routes: ' + e; });
</script>
</body>
</html>
"""

func pageHtml*(dataName, title: string): Option[string] =
  ## The page for the GeoJSON file `dataName` (a name of the cache directory, which is
  ## what makes it safe to put in the page).  None if the name is not one.
  if not isCacheFileName(dataName) or not dataName.endsWith(".geojson"):
    return none(string)
  some(template1.fill({"TITLE": htmlEscape(title), "CDN": cdn, "CSSHASH": leafletCssHash,
                       "JSHASH": leafletJsHash, "TILES": tiles, "DATA": dataName}))

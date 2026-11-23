import std/[math, options, os, strformat, unittest]
import nimchoo/packages/db/[sqltext, statement, store]
import nimchoo/packages/near/distance
from nimchoo/registry import allFragments, allAccess

suite "near: whether a line comes within a distance, quickly":
  test "the bounds hold: surely within is no further than the radius, surely beyond is no nearer":
    for lat in [0.0, -33.4, 51.5, 70.0, -85.0]:
      for metres in [100.0, 10_000.0, 100_000.0]:
        let (sure, maybe) = bounds(lat, metres)
        check sure * 111_700 <= metres and sure < maybe
        check maybe * 111_320 * cos(degToRad(min(89.9, abs(lat)))) >= metres
  test "the answer is the exact distance's, near the edge of the circle too":
    let path = getTempDir() / "nch-test-near-distance.db"
    removeFile(path)
    let st = openStore(path, allFragments, allAccess)
    defer:
      st.close()
    for lat in [-33.43, 0.0, 60.0]:
      let lon = -70.6
      for metres in [1000.0, 10_000.0]:
        # a north-south line to the east of the point, its distance just under and just over the radius, and far
        let perDegree = 111_320.0 * cos(degToRad(lat)) # (of longitude, at that latitude)
        for away in [0.0, 0.5, 0.99, 1.01, 1.5, 3.0]:
          let x = lon + away * metres / perDegree
          let line = fmt"LINESTRING({x} {lat - 1}, {x} {lat + 1})"
          let q =
            sqlOf("select ") &
            withinSql("GeomFromText(:line, 4326)", "p", lat, metres)
            .with("line", line)
            .with("pLon", lon)
            .with("pLat", lat)
            .with("pM", metres) &
            sqlOf(
              ", ST_Distance(GeomFromText(:line2, 4326), MakePoint(:lon2, :lat2, 4326), 1) <= :m2"
            )
            .with("line2", line)
            .with("lon2", lon)
            .with("lat2", lat)
            .with("m2", metres)
          let (quick, exact) = st.db.queryOne(tuple[quick, exact: int], q).get
          checkpoint fmt"lat {lat}, {metres} m, {away} of the radius away"
          check quick == exact

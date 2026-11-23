## The pages the server may run, as `map` and `plot` offer them (made from their own options): for the tests of the server's
## checks that need pages without the whole registry.

import ../../src/nimchoo/packages/map/params as mapParams
import ../../src/nimchoo/packages/plot/params as plotParams
import ../../src/nimchoo/packages/subject/subjects
import ../../src/nimchoo/packages/web/request

let
  mapPage* = pageOf("map", mapSpec(), isWord)
  plotPage* = pageOf("plot", plotSpec(), isWord)
  testPages* = @[mapPage, plotPage]

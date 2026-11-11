## The pages the server may run, as `map` and `ff` offer them (made from their own options): for the tests of the server's
## checks that need pages without the whole registry.

import ../../src/nimchoo/packages/ff/params as ffParams
import ../../src/nimchoo/packages/map/params as mapParams
import ../../src/nimchoo/packages/web/request

let
  mapPage* = pageOf("map", mapSpec(), "selection")
  ffPage* = pageOf("ff", ffSpec(), "state")
  testPages* = @[mapPage, ffPage]

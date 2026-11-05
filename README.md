
# nimchoo

nimchoo is a rewrite of my choochoo project, which was an
over-ambitious kinda-strava.  unlike choochoo, nimchoo:

* stays focussed on the command line (no sneaking off trying to be
  strava, or repairing fits files, or...)

* uses an embedded database (no more worrying about postgresql)

* is written in a single, fast language (no more python or pandas)

* should be easy to install (like, we might even have exacutables)

* is unlikely to care about power meters

but it does keep:

* some smart ideas about fit parsing, auto-detection of climbs and
  segments

* GIS in the database

* the ability to display complex data via web technologies

those decisions (particularly command line and no power) make it
pretty boutique.  that's ok.  and, on the other hand, it will be
easier to use.  i am also trying hard to make it extensible.  so if
someone else does come along, they can contribute more easily.

finally, one significant difference - nimchoo is firmly developed with
ai (claude code).  this simplifies hugely the amount of work that goes
into extracting snippets from choochoo and rewriting them as nim.  i'm
on the fence about ai in general, but as a software engineering tool
it blows my mind.

## eye candy

i'll try get some screenshots here soon.

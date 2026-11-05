
# nimchoo

* is a small, fast, local, **cli toolkit for fits files** like you can
  download from sports watches and bike computers.

* it stores fits data in a **local database** (no data shared; nothing
  in the cloud; you can open it up with standard tools and see what is
  inside).

* **analysis** of routes, performance, records, etc.

* **display** of results at the terminal and in a web browser.

* automatic **detection of climbs and segments** in activities.

* **automatic naming** of activities, climbs.

* heart rate based **fitness / fatigue** models, with user-adjustable
  parameters.

* open source, hackable, extensible.

* full control of data and disk use (cache management), although it
  does require internet access for many operations.

## background

nimchoo is a rewrite of my choochoo project, which was an
over-ambitious kinda-strava.  unlike choochoo, nimchoo:

* stays focussed on the **command line** (no sneaking off trying to be
  strava, or repairing fits files, or...)

* uses an **embedded database** (no more worrying about postgresql)

* is written in a single, **fast** language (no more python or pandas;
  lightning fast fit import)

* should be **easy to install** (like, we might even have executables)

* is unlikely to care about power meters

but it does keep:

* some **smart ideas** about fit parsing, auto-detection of climbs and
  segments

* **gis** in the database (inbuilt support for gegraphic operations).

* the ability to **display complex data in your web browser**.

those decisions (particularly command line and no power) make it
pretty boutique.  that's ok.  i am also trying hard to make it extensible. 
so if someone else does come along, they can contribute more easily.

finally, one significant difference - nimchoo is firmly developed with
ai (claude code).  this simplifies hugely the amount of work that goes
into extracting snippets from choochoo and rewriting them as nim.  i'm
on the fence about ai in general, but as a software engineering tool
it blows my mind.

if i had to choose one thing that makes nimchoo stand out it's the cli
user interface.  you would not believe the time i have spent obsessing
over command parameters.

## eye candy

i'll try get some screenshots here soon.

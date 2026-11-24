## What `nch activities` is asked to do, as a value that cannot say what makes no sense.
##
## An **action** (show them, delete them, name them again) on a **scope** (the selection, every activity, or those that match
## **filters**).  The command line is parsed into one (`criteria.parseArgs`); the combinations the options could be given in that
## mean nothing (`--delete -v`, `--rename --select`, `--all` with a criterion, `--newest` with `--oldest`) are refused there and
## are not representable here.
##
## Two stages of filters, two types.  A `Filter` is a criterion as it was typed: a value that may refer to `latest` or `previous`
## (an activity found when the command runs), a number that may be an activity's, the words another package resolves.  A
## `Resolved` filter has its values (`criteria.matchSql` takes only these, so no reference can reach the SQL).  `refersTo` and
## `withoutLatest` are each one `case` over the kind of filter with no `else`: a new criterion does not compile until every place
## handles it.  Pure.

import std/options
import ../fit/time
import ../db/sqltext
import ../ui/units
import ../subject/subjects
import ../tags/tag
import ./[criterion, ranges]
export Among

{.push raises: [].}

type
  Listed* = object
    ## `--names`, `--starts`: the values given, and perhaps the one of another activity.
    values*: seq[string]
    refers*: Option[Referent]

  Spread* = object
    ## `--distance`, `--active`: a range, or around that of another activity.
    case byReference*: bool
    of false:
      range*: NumRange
    of true:
      refers*: Referent
      tol*: Tol

  PlaceKind* = enum
    plPoint
    plPlace
    plReferent

  Place* = object ## `--from`, `--near`: where.
    case kind*: PlaceKind
    of plPoint:
      lat*, lon*: float
    of plPlace:
      name*: string
        ## a landmark, else the biggest place of that name among the names loaded
    of plReferent:
      refers*: Referent ## where that activity started

  Gps* = enum
    gpsWith ## --gps: only activities with at least one position
    gpsWithout ## --no-gps: only those without any

  FilterKind* = enum
    ftNames
    ftStarts
    ftPaths
    ftTags
    ftContributed
    ftDistance
    ftActive
    ftAfter
    ftBefore
    ftGps
    ftFrom
    ftNear

  Filter* = object ## One criterion, as given.
    case kind*: FilterKind
    of ftNames, ftStarts:
      listed*: Listed
    of ftPaths:
      paths*: seq[string]
        ## text found in a path the file was imported from (or in its name)
    of ftTags:
      patterns*: seq[TagPattern] ## --tags: the activity has a tag matching each ("and")
    of ftContributed:
      contributed*: Contributed
        ## an option that another package offers (`--climbs`), as given
    of ftDistance, ftActive:
      spread*: Spread ## metres, seconds
    of ftAfter, ftBefore:
      at*: UnixTime ## the activity starts at or after (before) this instant
    of ftGps:
      gps*: Gps
    of ftFrom, ftNear:
      place*: Place
      radius*: Option[Distance] ## none: each its default (`near.startKm`, `passKm`)

  ResolvedKind* = enum
    ## In the order the conditions are written in the SQL.
    rtNames
    rtStarts
    rtPaths
    rtTags
    rtCondition
    rtDistance
    rtActive
    rtGps
    rtAfter
    rtBefore
    rtFrom
    rtNear

  Resolved* = object
    ## One criterion with its values: nothing in it refers to an activity that is yet to be found.
    case kind*: ResolvedKind
    of rtNames, rtStarts:
      typed*: seq[string]
        ## text found in the value, whatever its case and accents; "none": nothing
      exact*: seq[Option[string]]
        ## the whole value (what `latest` or `previous` came to; none: it has none)
      ids*: seq[int64] ## the activities a whole number meant (names only)
    of rtPaths:
      paths*: seq[string]
    of rtTags:
      tags*: seq[TagPattern]
    of rtCondition:
      condition*: Sql
        ## from the package that offers the criterion: true for the activities that meet it
    of rtDistance, rtActive:
      range*: NumRange ## metres, seconds (open: any)
    of rtGps:
      gps*: Gps
    of rtAfter, rtBefore:
      at*: UnixTime
    of rtFrom, rtNear:
      lat*, lon*: float
      km*: float ## the radius

  Anchor* = object
    ## What an activity that a criterion refers to (the latest, the previous) is, as far as a criterion can use it.
    distanceM*, activeS*: Option[float]
    name*, startPlace*: Option[string] ## none: not recorded
    start*: Option[(float, float)]
      ## where it started (latitude, longitude); none if it has no positions

  LimitKind* = enum
    lkNewest
    lkOldest

  Limit* = object
    ## `--newest N`, `--oldest N`: only that many of those that match, by start time.
    kind*: LimitKind
    count*: int ## 1 or more

  ActionKind* = enum
    akList ## show them
    akDelete ## delete them (and everything made from them)
    akRename ## name them again

  Action* = object
    case kind*: ActionKind
    of akList:
      verbose*: bool ## -v: show more of each activity
      select*: bool
        ## --select: what is listed replaces the selection (the usage's steps)
    of akDelete, akRename:
      discard ## (they show nothing: no `-v`, no `--select`)

  ScopeKind* = enum
    scSelection ## no criteria and no `--all`: the selection kept in the database
    scAll ## --all: every activity (not just the selection)
    scMatching ## those that meet the filters

  Scope* = object
    case kind*: ScopeKind
    of scSelection:
      discard
    of scAll:
      allLimit*: Option[Limit] ## `--all --newest 3`
    of scMatching:
      filters*: seq[Filter]
        ## each kind at most once, except the contributed ones; not empty unless there is a limit
      invert*: bool
        ## --invert: the activities that do NOT meet the filters (before the limit); there is a filter to invert
      among*: Among ## --within: only the selection is searched
      also*: bool ## --also: the selection is added to what is found
      limit*: Option[Limit]

  Request* = object
    action*: Action
    scope*: Scope

func limitOf*(s: Scope): Option[Limit] =
  ## The limit of the scope, if it has one (the selection has none).
  case s.kind
  of scSelection:
    none(Limit)
  of scAll:
    s.allLimit
  of scMatching:
    s.limit

func searches*(s: Scope): bool =
  ## Whether the activities are searched for among all of them (not the selection kept).
  s.kind != scSelection

func filtersOf*(s: Scope): seq[Filter] =
  ## The filters of a scope that has them (none for the others).
  case s.kind
  of scMatching:
    s.filters
  of scSelection, scAll:
    @[]

func amongOf*(s: Scope): Among =
  ## Where the scope's search looks (the selection is the selection, and `--all` every activity).
  case s.kind
  of scSelection, scAll: amEvery
  of scMatching: s.among

func inverts*(s: Scope): bool =
  ## Whether the activities that do NOT meet the filters are meant.
  s.kind == scMatching and s.invert

func refersTo*(f: Filter, r: Referent): bool =
  ## Whether the criterion is measured against the activity `r` stands for.
  case f.kind
  of ftNames, ftStarts:
    f.listed.refers == some(r)
  of ftDistance, ftActive:
    f.spread.byReference and f.spread.refers == r
  of ftFrom, ftNear:
    f.place.kind == plReferent and f.place.refers == r
  of ftPaths, ftTags, ftContributed, ftAfter, ftBefore, ftGps:
    false

func usesLatest*(filters: seq[Filter]): bool =
  ## Whether a criterion refers to "latest".
  for f in filters:
    if f.refersTo(rfLatest):
      return true

func usesPrevious*(filters: seq[Filter]): bool =
  ## Whether a criterion refers to "previous".
  for f in filters:
    if f.refersTo(rfPrevious):
      return true

func withoutLatest*(f: Filter): Option[Filter] =
  ## The criterion without what refers to `latest` (none if that was all of it): the activities that meet what is left are
  ## those among which "latest" is found.
  case f.kind
  of ftNames, ftStarts:
    if f.listed.refers == some(rfLatest):
      if f.listed.values.len == 0:
        none(Filter)
      else:
        var rest = f
        rest.listed.refers = none(Referent)
        some(rest)
    else:
      some(f)
  of ftDistance, ftActive:
    if f.refersTo(rfLatest):
      none(Filter)
    else:
      some(f)
  of ftFrom, ftNear:
    if f.refersTo(rfLatest):
      none(Filter)
    else:
      some(f)
  of ftPaths, ftTags, ftContributed, ftAfter, ftBefore, ftGps:
    some(f)

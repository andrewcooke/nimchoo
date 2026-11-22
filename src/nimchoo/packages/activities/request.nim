## What `nch activities` is asked to do, as a value that cannot say what makes no sense: an **action** (show them, delete them,
## name them again) on a **scope** (the selection, every activity, or those that match criteria).  The command line is parsed
## into one (`criteria.parseArgs`); the combinations the options could be given in that mean nothing (`--delete -v`, `--rename
## --select`, `--all` with a criterion, `--newest` with `--oldest`) are refused there and are not representable here.  Pure.

import std/options
import ../fit/time
import ../near/near
import ../ui/units
import ./[criterion, ranges]

{.push raises: [].}

type
  Points* = object
    ## the points `--from` and `--near` came to, once a place, `latest` and `previous` are worked out: (lat, lon)
    start*, passes*: Option[(float, float)]

  GpsFilter* = enum
    gfAny
    gfWith
    gfWithout
      ## --gps: only activities with at least one position; --no-gps: only those without any

  Relative* = object
    ## `latest~10%`: around an activity that is found when the command runs.
    refers*: Reference
    tol*: Tol

  Criteria* = object
    ## Which activities, as the options that pick them were given.  (None given: every field is as `Criteria()`.)
    distanceM*, activeS*: NumRange ## --distance, --active (metres, seconds; open: any)
    distanceRel*, activeRel*: Option[Relative]
      ## --distance latest~T / previous~T, --active ...
    sportRef*, subSportRef*: Reference ## --sports latest / previous, --sub-sports ...
    sports*, subSports*: seq[string]
      ## only these (lower case; "none": not recorded); empty: any
    nameRef*, startRef*: Reference ## --names latest / previous, --starts ...
    names*, starts*: seq[string]
      ## --names, --starts: text found in the name (the start place), whatever its case and
      ## accents; "none": nothing; empty: any
    namesExact*, startsExact*: seq[string]
      ## what `latest` / `previous` came to: the whole value ("" is none)
    nameIds*: seq[int64]
      ## the activities a whole number in `--names` meant, when no name held it (worked out when the command runs)
    paths*: seq[string]
      ## --paths: text found in a path the file was imported from (or in its name)
    contributed*: seq[Contributed]
      ## the options that other packages offer (`--climbs`), as given: they are resolved when the command runs
    afterT*: Option[UnixTime] ## the activity starts at or after this instant
    beforeT*: Option[UnixTime] ## the activity starts before this instant
    gps*: GpsFilter
    start*: Spot ## --from: where the activity starts
    passes*: Spot ## --near: a point its route passes
    radius*: Option[Distance] ## --radius (none: each its default)

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
      select*: bool ## --select: keep what is listed as the selection
    of akDelete, akRename:
      discard ## (they show nothing: no `-v`, no `--select`)

  ScopeKind* = enum
    scSelection ## no criteria and no `--all`: the selection kept in the database
    scAll ## --all: every activity (not just the selection)
    scMatching ## those that meet the criteria

  Scope* = object
    case kind*: ScopeKind
    of scSelection:
      discard
    of scAll:
      allLimit*: Option[Limit] ## `--all --newest 3`
    of scMatching:
      criteria*: Criteria
      invert*: bool
        ## --invert: the activities that do NOT meet the criteria (before the limit); there is a criterion to invert
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

func criteriaOf*(s: Scope): Criteria =
  ## The criteria of a scope that has them (none given, for the others).
  case s.kind
  of scMatching:
    s.criteria
  of scSelection, scAll:
    Criteria()

func inverts*(s: Scope): bool =
  ## Whether the activities that do NOT meet the criteria are meant.
  s.kind == scMatching and s.invert

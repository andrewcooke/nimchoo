## The frames of a plot: what the packages that manage a subject contribute for the plot to draw.  The plot is a view; a
## frame is a set of series over time about a subject (a CSV file), made by the package that knows the subject, so the plot
## needs nothing of the packages above it.  This is an extension point of this package (`plotFramePoint`).
##
## A frame says which subject it is a frame of, its name, what it is, whether a plot of that subject shows it unless told
## otherwise, whether it reads the selection of the subject, which tables it reads, what its values are (`unit`, the label
## of its axis), how its series are drawn (`mark`: lines, or bars a day wide), and its **axis**, which says how it is made:
## over **days** (`axDays`: for a period of time, as the impulse and the fitness are) or over the time of **one activity**
## (`axActivity`: for an activity, by its id, as its heart rate is; the page overlays the activities ticked, each from
## its start; a frame whose values grow along the activity, `along`, can be the x axis instead: the distance).  The frames
## of a subject share an axis (a test checks it): the page draws them on one.  A frame gives its
## series (each a name and its points; a NaN value breaks a line: a pause) and, for `--file`, lines said after the files
## (the latest values).  A frame that fails raises `StoreError` with what to say.  The page draws each frame shown in a
## panel of its own, one above the other, on the same axis.

import std/[options, times]
import ../../core/[errors, extension, ids, line]
import ../user/session

{.push raises: [].}

type
  Mark* = enum ## How a frame's series are drawn.
    mkLine ## a line through the points
    mkBar ## a bar for each point, a day wide (the point is the start of its day)
    mkRule
      ## a vertical line at each point, across every panel (not a panel of its own): marks of a time (the breaks of a
      ## ride); its series are styles, told apart by the order they come in (the first solid, then dashed ...), and a
      ## point's value is said on hover

  Point* = tuple[t: int64, value: float] ## an instant (Unix seconds) and a value

  Series* = object ## One line (or set of bars) of a frame.
    name*: string ## "default": what the legend says
    points*: seq[Point] ## in time order

  Period* = object ## The period of time a plot shows.
    first*: Option[int64]
      ## the instant it starts (`--after`); none: as early as there are data
    last*: int64
      ## the instant it ends: the end of the last day (`--before`, else of today)
    now*: int64 ## when it is made
    zone*: Timezone ## whose days: the user's (this computer's)

  PlotData* = object ## What a frame made.
    series*: seq[Series]
    notes*: seq[Line] ## said after the files with `--file` (the latest values, ...)
    warnings*: seq[Line] ## said to the user ("no model is selected")

  MakePlot* =
    proc(st: Session, period: Period): PlotData {.nimcall, raises: [StoreError].}
    ## Make the frame from the data as they are now, for the user of the session.  It may write what it needs worked out
    ## first (the impulses), in a transaction of its own.

  MakeActivityPlot* =
    proc(st: Session, activity: ActivityId): PlotData {.nimcall, raises: [StoreError].}
    ## Make the frame of one activity from the data as they are now (a series of its points at their own times: the page
    ## puts them from the activity's start).

  Axis* = enum ## What a frame is drawn over, and so how it is made.
    axDays ## days: made for a period of time
    axActivity ## the time of one activity: made for an activity

  PlotFrame* = object
    subject*: string ## the subject it is a frame of ("ff")
    name*: string
      ## what the user types after `--frames` ("fitness"); unique within the subject
    summary*: string ## one line
    shown*: bool ## drawn when `--frames` is not given
    readsSelection*: bool ## whether it is made from the selection of the subject
    tables*: seq[string] ## the tables it reads
    unit*: string ## what its values are: the label of its axis
    mark*: Mark
    styles*: seq[string]
      ## for rules: the names of its series in the order the page styles them (solid, dashed, dotted ...), so that a name
      ## has one style whichever of them a ride has
    case axis*: Axis
    of axDays:
      make*: MakePlot
    of axActivity:
      makeActivity*: MakeActivityPlot
      along*: bool
        ## its values grow along the activity (the distance), so the page offers it as the x axis instead of the time; as a
        ## panel it is worth ticking with several activities (who was ahead, and when), and it is hidden while it is the x
        ## axis (against itself it would be a diagonal)

const plotFramePoint* = ExtensionPoint[PlotFrame](name: "plot/frames")
  ## The frames the packages that manage a subject offer the plot.

func framesOf*(all: seq[PlotFrame], subject: string): seq[PlotFrame] =
  ## The frames of a subject, in the order they were contributed.
  for f in all:
    if f.subject == subject:
      result.add f

func inPeriod*(period: Period, t: int64): bool =
  ## Whether an instant is in the period.
  (period.first.isNone or t >= period.first.get) and t <= period.last

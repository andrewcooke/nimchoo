## When two neighbouring timer segments are one stretch of riding.
##
## A Garmin stops the timer by itself ("auto-pause") when the rider slows
## down, at a junction or to drink, and starts it again when they move.  That
## is not a break in the ride: a climb with a drink stop half way is one
## climb, and a time from gate to gate includes the stop (a rider who does not
## stop earns the faster time).  What is a break is a gap in which the rider
## was carried (a car, a train) or the timer was stopped by hand.  The rule
## here tells them apart from what the file says (who stopped and restarted
## the timer) and what the rider did (how far they were from where they
## stopped, in how long).  Measured on 55,171 gaps of the author's rides it
## joins 99.3%; the rest are manual stops, long gaps that moved, and short
## ones that moved too far to be explained by the rider's own speed.
##
## Pure: the importer measures the gap and asks.

{.push raises: [].}

const
  stillM* = 30.0
    ## A gap in which the rider ended less than this far from where they
    ## stopped is a pause, however long (a drink, a photo, a café).
  quickS* = 30'i64
    ## A gap shorter than this is the timer blinking off while the rider
    ## carried on, if the speed it implies is one a bicycle can do.  The limit
    ## is short so that a vehicle cannot hide in it: the longest jump it can
    ## join is `quickS` times `ridingMps`.
  ridingMps* = 15.0 ## 54 km/h: a fast descent, not a car.

type
  Trigger* = enum
    ## Who stopped or restarted the timer (the `timer_trigger` of the FIT
    ## event).
    trAuto
    trManual

  Gap* = object ## The time between one timer segment and the next.
    seconds*: int64 ## from the stop to the restart
    metres*: float ## from the last position before the stop to the first after
    stoppedBy*, restartedBy*: Trigger

func joinable*(g: Gap): bool =
  ## True if the segments on either side of `g` are one stretch.  A timer
  ## stopped or started by hand always separates them: it is the rider's way
  ## to say "this is apart".
  doAssert g.seconds >= 0 and g.metres >= 0, "a gap has a length and a duration"
  if g.stoppedBy == trManual or g.restartedBy == trManual:
    return false
  if g.metres < stillM:
    return true
  g.seconds < quickS and g.metres / float(max(g.seconds, 1)) < ridingMps

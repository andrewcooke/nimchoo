## Intervals of time as text: ONE rule for the whole program, so a duration looks the
## same in every listing.
##
##     45s    22m05s    4h41m    2d03h07m
##
## * units are d, h, m, s, the largest first, no leading unit that is zero;
## * the first unit has no padding and the ones after it have two digits (`4h05m`);
## * under an hour the seconds are shown (`22m05s`); from an hour they are not, and the
##   interval is rounded to the minute (`4h41m`); from a day it is `2d03h07m`;
## * a zero after the first unit is kept (`1h00m`), so columns line up;
## * under a minute it is just seconds (`45s`), and nothing is `0s`.

import std/[math, strutils]

{.push raises: [].}

func interval*(seconds: float): string =
  ## `seconds` as text by the rule above.  Negative or not a number counts as zero.
  let s = if seconds != seconds or seconds < 0: 0.0 else: seconds
  # rounded to the minute from an hour (so 3,599.7 s rounds to the second first)
  let total =
    if s >= 3600:
      int64(round(s / 60.0)) * 60
    else:
      int64(round(s))
  let days = total div 86400
  let hours = (total mod 86400) div 3600
  let minutes = (total mod 3600) div 60
  let secs = total mod 60
  if total >= 86400:
    $days & "d" & intToStr(int(hours), 2) & "h" & intToStr(int(minutes), 2) & "m"
  elif total >= 3600:
    $hours & "h" & intToStr(int(minutes), 2) & "m"
  elif total >= 60:
    $minutes & "m" & intToStr(int(secs), 2) & "s"
  else:
    $secs & "s"

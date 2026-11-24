## A place by its name, for a command that takes one where a position is wanted (`nch activities --from Providencia`): the
## author's landmarks first, then the GeoNames features already loaded (`feature`: the cells where the rides are; nothing
## is downloaded), compared without regard to case or accents.  Among the features, populated places come first, the
## biggest first; then the rest, the biggest first.  A name may mean the places with it whole, then those with it as a
## word of their name (`toyo` of "El Toyo"), then those with it anywhere in their name (`toy`), each kind in that order
## (`Match`).  A command that searches by the place tries them in turn (`Finds`: whether its search finds something
## near), and takes the first that does, else the first of all (decided with the author 2026-11-25: "toyo" means the Toyo
## among your rides; the step is in the usages of `activities` and `climbs`).  Pure database code.

import std/[options, sequtils, strformat, strutils]
import ../db/[sqltext, statement]
import ../db/store
import ../../core/errors
import ./codes

{.push raises: [].}

type
  NamedPlace* = object
    name*: string ## as it is spelt there
    lon*, lat*: float
    what*: string
      ## "your landmark", "a populated place (PPLA3, CL)", "a feature (HLL, CL)"

  Finds* = proc(lat, lon: float): bool {.closure, raises: [StoreError].}
    ## Whether the search a place is wanted for would find anything near it.

  Chosen* = tuple[lat, lon: float, said: string]
    ## the place taken, and what to say about the choice

type Match* = enum ## How a name was matched, the closest first.
  mWhole ## the place has that name
  mWord ## it is a word of the place's name ("toyo" of "El Toyo")
  mPart ## it is anywhere in the place's name ("toy" of "El Toyo")

const
  matchSql: array[Match, string] = [
    mWhole: "fold(name) = fold(:text)",
    mWord: "instr(' ' || fold(name) || ' ', ' ' || fold(:text) || ' ') > 0",
    mPart: "instr(fold(name), fold(:text)) > 0",
  ]
    ## the condition each is (on the folded name and `:text`: a value, so `%` or `_` in it means nothing)
  othersSaid = 3 ## the other candidates named in what is said; the rest are counted

proc placesWhere(
    st: Store, m: Match, text: string
): seq[NamedPlace] {.raises: [StoreError].} =
  ## The landmarks and the features whose folded name matches `text` as `m` says, in their order.
  let condition = sqlOf(matchSql[m]).with("text", text)
  for r in st.db.query(
    tuple[name: string, lon, lat: float],
    sqlOf("select name, lon, lat from landmark where ") & condition &
      sqlOf(" order by name"),
  ):
    result.add NamedPlace(name: r.name, lon: r.lon, lat: r.lat, what: "your landmark")
  for r in st.db.query(
    tuple[
      name, class, code, country: string, population: Option[int64], lon, lat: float
    ],
    sqlOf(
      "select name, class, code, country, population, X(geom), Y(geom) from feature where "
    ) & condition &
      sqlOf(
        " and geom is not null order by class = 'P' desc, coalesce(population, 0) desc, id"
      ),
  ):
    if r.class == "P" and r.code.isInactivePlace:
      continue
    let what =
      if r.class == "P":
        fmt"a populated place ({r.code}, {r.country})"
      else:
        fmt"a feature ({r.code}, {r.country})"
    result.add NamedPlace(name: r.name, lon: r.lon, lat: r.lat, what: what)

proc placesMatching*(
    st: Store, text: string, m: Match
): seq[NamedPlace] {.raises: [StoreError].} =
  ## The places whose name matches `text` in the way `m` says (and not in a closer one), the likeliest first.
  let t = text.strip
  if t.len == 0:
    return
  var closer: seq[NamedPlace]
  for c in Match:
    if c == m:
      break
    closer.add placesWhere(st, c, t)
  for p in placesWhere(st, m, t):
    if closer.allIt(it.name != p.name or it.lon != p.lon or it.lat != p.lat):
      result.add p

func describe*(p: NamedPlace): string =
  ## "El Toyo, a feature (FRM, CL)".
  fmt"{p.name}, {p.what}"

func how(m: Match, text: string): string =
  case m
  of mWhole:
    ""
  of mWord:
    fmt"; no place is called '{text}': this has it as a word of its name"
  of mPart:
    fmt"; no place is called '{text}' or has it as a word: this has it in its name"

func said(
    p: NamedPlace, m: Match, text: string, found: seq[NamedPlace], k: int, finding: bool
): string =
  ## What is said of the choice: which, how it was matched, whether the search finds anything near it, and the others of
  ## its kind ("also Toyo Alto, ...; and 4 more").
  result = p.describe & how(m, text)
  if not finding:
    result.add "; your search finds nothing near it, nor near any other place the name may mean"
  elif k > 0:
    result.add "; the likeliest that your search finds something near"
  var others: seq[string]
  for i, q in found:
    if i != k and others.len < othersSaid:
      others.add q.describe
  let more = found.len - 1 - others.len
  if others.len > 0:
    result.add "; also " & others.join("; ") &
      (if more > 0: fmt"; and {more} more" else: "")

proc placeNamed*(
    st: Store, text: string, finds: Finds
): Chosen {.raises: [StoreError].} =
  ## The place `text` means for a search (the step the usages of `activities` and `climbs` say): the places it may mean,
  ## those with that name, then with it as a word of their name, then with it anywhere in their name, each the likeliest
  ## first, are tried in turn (`finds`), and the first near which the search finds something is taken; if none is, the
  ## first of them; and what to say about the choice.  A `StoreError` that says what to do if no place matches at all.
  var first: Option[(NamedPlace, Match, seq[NamedPlace])]
  for m in Match:
    let found = placesMatching(st, text, m)
    if found.len == 0:
      continue
    if first.isNone:
      first = some((found[0], m, found))
    for i, p in found:
      if finds(p.lat, p.lon):
        return (p.lat, p.lon, said(p, m, text, found, i, true))
  if first.isNone:
    raiseStore(
      fmt"no place is called '{text}', or has it in its name, among your landmarks (`nch landmarks`) and the places the names were loaded for (round your rides): give LAT,LON instead"
    )
  let (p, m, found) = first.get
  (p.lat, p.lon, said(p, m, text, found, 0, false))

proc placeNamed*(st: Store, text: string): Chosen {.raises: [StoreError].} =
  ## The likeliest place `text` means, where there is no search to try it with (the first of those it may mean).
  placeNamed(
    st,
    text,
    proc(lat, lon: float): bool {.closure, raises: [StoreError].} =
      true,
  )

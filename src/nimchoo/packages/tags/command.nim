## `nch tags`: the tags of the activities, and adding, removing and renaming them.  What it works on follows the steps in its
## usage (`params.nim`); the work is in `found.nim`.

import std/[options, sequtils, strformat, strutils]
import ../../core/[ask, errors, globals, line, logfile, ruled, unitfix]
import ../util/args/[args, usage]
import ../ui/[units, vocabulary]
import ../user/session
import ./[found, params, tag]

{.push raises: [].}

const commandName* = "tags" ## what the user types after `nch`

proc options*(g: Globals): seq[OptDoc] {.nimcall, raises: [].} =
  ## The options of `nch tags`, described (for tab completion).
  tagSpec().docs

const
  synopsis =
    """usage: nch [--db PATH] [--user NAME] tags [--all | --names PATTERN... [--within]] [--add TAG... | --delete | --rename NEW]"""
  intro = @[
    ~"Show the tags of your activities, with how many have each; add, remove and rename them.  What it works on is found in these steps:",
    ~"1. Start with the tags of all your activities.",
    ~"2. If `--within`, keep only those of the selected activities.",
    ~"3. If `--names`, keep only the tags matching.",
    ~"4. If `--delete`, remove those tags; if `--rename NEW`, rename the one tag found; if `--add TAG...`, add the tags to the activities that have the tags found.",
    ~"5. Display the result: each tag with how many activities have it.",
    ~"If no criteria are given, steps 2 and 3 are skipped and the tags of the current selection are used (with `--add`, the selected activities).  `--all` is the criterion that keeps everything.",
    ~"To work on chosen activities, choose them with `nch activities` first: `nch activities --names toyo --select`, then `nch tags --add hard`.  An import gives each activity its sport as a tag (`sport:cycling:road`), and the tags of a template in its path (`nch import -h`).",
  ]

proc usageText*(width: int): seq[Line] =
  ## The usage: the synopsis, the introduction and the options, wrapped to `width`.
  usageOf(synopsis, width, intro, tagSpec().docs)

func whatOf(scope: TagScope): string =
  ## What the scope is, said in a message.
  case scope.kind
  of tsSelection:
    "the selected activities"
  of tsAll:
    "all your activities"
  of tsMatching:
    (if scope.within: "the selected activities" else: "your activities")

proc table(g: Globals, rows: seq[tuple[tag: string, n: int]], total: int): seq[Line] =
  ## The tags as a table (each in `tag`), with the last line (alone if there are none).
  var cells: seq[seq[Line]]
  for r in rows:
    cells.add @[~"<tag {r.tag}>", plain(count(r.n))]
  if rows.len > 0:
    for l in ruledRows(@["tag", "activities"], cells, g.textWidth(osOut), right = {1}):
      result.add l.line
  result.add doneLine(listDone(rows.len, some(total), "tag", "tags"))

proc run*(g: Globals, args: seq[string]): int {.raises: [].} =
  ## Entry point for `nch tags ARGS`; returns the exit status.
  let parsed = parseArgs(args)
  case parsed.kind
  of pkHelp:
    g.showAll osOut, usageText(g.textWidth(osOut))
    return exitOk
  of pkProblem:
    return usageError(g, "nch tags", usageText(g.textWidth(osErr)), parsed.why)
  of pkUnit:
    return unitRetry(g, "nch tags", parsed.fix, run)
  of pkOk:
    discard
  let p = parsed.params
  try:
    let st = openSession(g)
    defer:
      st.close()
    if p.scope.kind == tsSelection and st.activityCount(p.scope) == 0:
      g.warn ~"nothing is selected: `nch activities CRITERIA --select` chooses activities, or give `--names` or `--all`"
      return exitOk
    case p.action.kind
    of taList:
      discard
    of taAdd:
      let r = st.addTo(p.scope, p.action.tags)
      let tags = p.action.tags.mapIt($it).join(" ")
      let n = counted(r.activities, "activity", "activities")
      let said = fmt"added {tags} to {n} ({count(r.added)} new)"
      g.log.log(lvInfo, commandName, leSaved, said)
      g.done(~"{said}")
    of taDelete:
      let found = st.counts(p.scope)
      if found.len == 0:
        g.warn ~"no tag is found: nothing to delete"
        return exitOk
      var removed = 0
      for f in found:
        removed += f.n
      let names = found.mapIt(it.tag).join(" ")
      let what =
        fmt"{counted(removed, ""tag"", ""tags"")} ({names}) from {whatOf(p.scope)}"
      if not confirmDelete(g, what, parsed.yes):
        return exitFailure
      let n = st.remove(p.scope)
      g.log.log(lvInfo, commandName, leDeleted, fmt"{n} tags ({names})")
      sayDeleted(g, fmt"deleted {what}")
      return exitOk
    of taRename:
      let old = $p.action.old
      let new = $p.action.new
      let merged = st.merges(p.scope, p.action.new)
      if merged > 0:
        let these = counted(merged, "activity has", "activities have")
        if not ask(
          g,
          @[
            warnLine(~"{these} {new} already: there the two become one"),
            ~"rename {old} to {new}?",
          ],
          true,
          parsed.yes,
        ):
          return exitFailure
      let n = st.rename(p.scope, p.action.new)
      let said =
        fmt"renamed {old} to {new} on {counted(n, ""activity"", ""activities"")}"
      g.log.log(lvInfo, commandName, leSaved, said)
      g.done(~"{said}")
    # what is shown is the result: after a rename, the tag under its new name
    let shown =
      case p.action.kind
      of taRename:
        TagScope(
          kind: tsMatching,
          patterns: @[parsePattern($p.action.new).pattern.get],
          within: p.scope.kind == tsMatching and p.scope.within,
        )
      of taList, taAdd, taDelete:
        p.scope
    let total = st.counts(TagScope(kind: tsAll)).len
    g.showAll(osOut, g.table(st.counts(shown), total))
    exitOk
  except StoreError as e:
    failure(g, "nch tags", e.msg)

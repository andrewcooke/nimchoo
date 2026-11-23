## The command line of `nch tags`, parsed.  Pure.
##
## It follows the steps of `nch activities`, with tags in place of activities: start with the tags of all your activities;
## with `--within` keep those of the selected ones; with `--names` keep those matching; then act on the result (`--delete`
## removes those tags, `--rename NEW` renames the one tag found, `--add TAG...` adds tags to the activities that have the
## tags found), and show it.  With no criteria the result is the tags of the selection; `--all` keeps everything.

import std/options
import ../util/args/args
import ./tag

{.push raises: [].}

type
  ScopeKind* = enum
    tsSelection ## no criteria: the tags of the selected activities
    tsAll ## --all: the tags of all the activities
    tsMatching
      ## --names: the tags matching any pattern, of all the activities or (--within) of the selected ones

  TagScope* = object ## Which tags (and so which activities) the command is about.
    case kind*: ScopeKind
    of tsSelection, tsAll:
      discard
    of tsMatching:
      patterns*: seq[TagPattern]
      within*: bool

  ActionKind* = enum
    taList
    taAdd
    taDelete
    taRename

  TagAction* = object
    case kind*: ActionKind
    of taList, taDelete:
      discard
    of taAdd:
      tags*: seq[Tag]
        ## added to the activities that have the tags of the scope (the selected ones, with no criteria)
    of taRename:
      old*, new*: Tag ## the one tag found (`--names` an exact tag), and its new name

  Params* = object
    scope*: TagScope
    action*: TagAction

  Raw = object ## what the options fill in
    help, all, within, delete: bool
    names: seq[TagPattern]
    add: seq[Tag]
    rename: Option[Tag]

proc takeNames(p: var Raw, name: string, values: seq[string]): Problem {.nimcall.} =
  for v in values:
    let r = parsePattern(v)
    if r.problem.isSome:
      return refuse(~"`{name}`: {r.problem.get}")
    p.names.add r.pattern.get
  if p.names.len == 0:
    return refuse(~"`{name}` needs a tag (`*` for anything: `bike:*`)")
  fine

proc takeAdd(p: var Raw, name: string, values: seq[string]): Problem {.nimcall.} =
  for v in values:
    let r = parseTag(v)
    if r.problem.isSome:
      return refuse(~"`{name}`: {r.problem.get}")
    p.add.add r.tag.get
  if p.add.len == 0:
    return refuse(~"`{name}` needs a tag")
  fine

func tagSpec*(): Spec[Raw] =
  ## The options of `nch tags`, in the order the usage lists them.
  Spec[Raw](
    opts: @[
      flag(
        Raw, ["--all"], all, ~"the tags of all your activities, not just the selection"
      ),
      listOption[Raw](
        ["--names"],
        takeNames,
        "PATTERN...",
        ~"only the tags matching any of the patterns, whatever the case or accents; `*` is anything: `--names 'bike:*'` (quoted, or the shell reads the `*`).  A criterion: it looks at all your activities",
      ),
      flag(
        Raw,
        ["--within"],
        within,
        ~"`--names` looks only at the tags of the selected activities",
      ),
      listOption[Raw](
        ["--add"],
        takeAdd,
        "TAG...",
        ~"add these tags to the activities that have the tags found (with no criteria, the selected activities; with `--all`, all of them)",
      ),
      flag(
        Raw,
        ["--delete"],
        delete,
        ~"remove the tags found from their activities (it asks first)",
      ),
      custom(
        Raw,
        ["--rename"],
        true,
        "NEW",
        ~"give the one tag found (`--names` with a whole tag, no `*`) the name NEW; where an activity has NEW already the two become one (it says so and asks)",
        body = (
          block:
            let r = parseTag(value)
            if r.problem.isSome:
              return refuse(~"`--rename`: {r.problem.get}")
            p.rename = r.tag
            fine
        ),
      ),
      helpFlag(Raw),
    ]
  )

func finish(raw: Raw): Parsed[Params] =
  func bad(why: Line): Parsed[Params] =
    problemWith[Params](why)

  let actions =
    (if raw.add.len > 0: 1 else: 0) + (if raw.delete: 1 else: 0) +
    (if raw.rename.isSome: 1 else: 0)
  if actions > 1:
    return bad(~"`--add`, `--delete` and `--rename` cannot be used together")
  if raw.all and (raw.names.len > 0 or raw.within):
    return bad(~"`--all` is every tag: it does not go with `--names` or `--within`")
  if raw.within and raw.names.len == 0:
    return bad(
      ~"`--within` narrows `--names` to the selection (`nch tags` alone shows the tags of the selection)"
    )
  let scope =
    if raw.all:
      TagScope(kind: tsAll)
    elif raw.names.len > 0:
      TagScope(kind: tsMatching, patterns: raw.names, within: raw.within)
    else:
      TagScope(kind: tsSelection)
  let action =
    if raw.add.len > 0:
      TagAction(kind: taAdd, tags: raw.add)
    elif raw.delete:
      TagAction(kind: taDelete)
    elif raw.rename.isSome:
      if raw.names.len != 1 or '*' in $raw.names[0]:
        return bad(
          ~"`--rename` renames one tag: name it whole with `--names` (`--names bike:uk --rename bike:hybrid`)"
        )
      TagAction(
        kind: taRename, old: parseTag($raw.names[0]).tag.get, new: raw.rename.get
      )
    else:
      TagAction(kind: taList)
  parsedOk(Params(scope: scope, action: action))

proc parseArgs*(args: seq[string]): Parsed[Params] =
  ## `nch tags [--all | --names PATTERN... [--within]] [--add TAG... | --delete | --rename NEW]`.
  parseCommand(args, tagSpec(), Raw(), finish)

## Tab completion: what a shell may offer for the word being typed, given the words before it.  Everything here is made
## from the options' descriptions (`OptDoc`: names, whether a value follows, what completes it), so the shell offers what
## the parser accepts and no list is kept twice.  The command line is `nch [HEAD OPTIONS] COMMAND [OPTIONS]`: the head
## options (`--db`, `--user`) come first, then a command, whose options are those it declares (`CommandDecl.options`).
##
## What is offered: the commands, the options (names; the long ones unless the word starts with a single `-`), the words
## of an option whose values are a fixed list, and file names for an option that takes a file (said to the shell, which
## knows files better than we do).  Nothing is offered where nothing is known (a positional word, an unknown option, an
## unknown command): the shell then has nothing to say, and that is not an error.  The values that come from the
## database are the option's own (`Completion.provide`): it is asked, with the `Globals` the caller made (read-only), and
## an error from it is no offer.
##
## No printing and no files of its own (`completion.nim` is the command); the providers read the database.

import std/[algorithm, sequtils, strutils]
import ./[errors, globals, manifest, optdoc]

{.push raises: [].}

type
  OfferKind* = enum
    okWords ## these words, which the shell may filter further
    okFiles ## file names: the shell knows them

  Offer* = object ## What to offer for the word being typed.
    case kind*: OfferKind
    of okWords:
      words*: seq[string] ## the ones that start with the word typed, each once
    of okFiles:
      discard

func nothing(): Offer =
  Offer(kind: okWords)

func withPrefix(words: openArray[string], prefix: string): Offer =
  ## The words that start with `prefix`, each once, in order.
  Offer(kind: okWords, words: words.filterIt(it.startsWith(prefix)).deduplicate)

func isOption(word: string): bool =
  word.len > 1 and word.startsWith("-")

func findDoc(docs: seq[OptDoc], name: string): int =
  ## Which option has this name, -1 if none.
  for k, d in docs:
    if name in d.names:
      return k
  -1

proc valueOffer(d: OptDoc, g: Globals, typed: string): Offer =
  ## What may be the value of this option.  A provider that cannot say (no database, a database of another version, a
  ## lock) offers nothing: that is the one place the tab key turns an error into silence.
  case d.completion.kind
  of ckNone:
    nothing()
  of ckDynamic:
    try:
      Offer(kind: okWords, words: d.completion.provide(g, typed).deduplicate)
    except StoreError:
      nothing()
  of ckFile:
    Offer(kind: okFiles)
  of ckWords:
    d.completion.words.withPrefix(typed)

func takesNext(d: OptDoc, word: string): bool =
  ## Whether `word`, right after the option `d`, is its value.
  case d.arity
  of aFlag, aList:
    false
  of aOne:
    true
  of aOptional:
    not word.isOption

func optionNames(docs: seq[OptDoc], typed: string): Offer =
  ## The names of the options that start with `typed`.  Before anything is typed only the long ones are offered: the
  ## short ones are for people who know them.
  var names: seq[string]
  for d in docs:
    for n in d.names:
      if typed.len > 0 or n.startsWith("--"):
        names.add n
  names.withPrefix(typed)

func normalise(words: seq[string]): seq[string] =
  ## Bash gives `--sport=cyc` as three words, `--sport`, `=` and `cyc` (it breaks words at `=`).  The `=` is not a word of
  ## ours: it goes, and one at the very end (the cursor is just after it) leaves an empty word being typed.
  for k, w in words:
    if w == "=" and k > 0 and words[k - 1].isOption:
      if k == words.high:
        result.add ""
    else:
      result.add w

proc scan(docs: seq[OptDoc], g: Globals, done: seq[string], typed: string): Offer =
  ## What the word being typed may be, after these words of a command: an option, or the value of the option before it.
  ## A word that is not an option is the value the option before it wants, else a positional (nothing is known about
  ## those) or one more value of a list option.
  var
    waiting = -1 ## the option that must have its value next
    listing = -1 ## the option whose list of values we are in
  for w in done:
    let was = waiting
    waiting = -1
    if was >= 0 and docs[was].takesNext(w):
      discard # (the value)
    elif w.isOption:
      listing = -1
      let k = docs.findDoc(w)
      if k >= 0:
        case docs[k].arity
        of aFlag:
          discard
        of aOne, aOptional:
          waiting = k
        of aList:
          listing = k
  if waiting >= 0 and not (docs[waiting].arity == aOptional and typed.startsWith("-")):
    docs[waiting].valueOffer(g, typed)
  elif typed.startsWith("-"):
    docs.optionNames(typed)
  elif listing >= 0:
    docs[listing].valueOffer(g, typed)
  else:
    docs.optionNames(typed)

proc complete*(
    head: seq[OptDoc], commands: seq[CommandDecl], g: Globals, line: seq[string]
): Offer =
  ## What to offer for the last word of `line`, the words after `nch` up to the one being typed (which may be empty).
  ## `head` describes the options that come before the command; `g` is for the commands that need it to say what their
  ## options are (those that other packages add to).
  let words = line.normalise
  if words.len == 0:
    return nothing()
  let typed = words[^1]
  let done = words[0 ..< words.high]
  var
    at = 0 ## the word that should be the command
    waiting = -1
  while at < done.len:
    let w = done[at]
    let was = waiting
    waiting = -1
    if was >= 0 and head[was].takesNext(w):
      discard # (the value)
    elif w.isOption:
      let k = head.findDoc(w)
      if k < 0:
        return nothing()
      if head[k].arity in {aOne, aOptional}:
        waiting = k
    else:
      break
    inc at
  if at >= done.len:
    # still among the options before the command
    if waiting >= 0 and not (head[waiting].arity == aOptional and typed.startsWith("-")):
      return head[waiting].valueOffer(g, typed)
    if typed.startsWith("-"):
      return head.optionNames(typed)
    return commands.mapIt(it.name).sorted.withPrefix(typed)
  let named = commands.filterIt(it.name == done[at])
  if named.len == 0 or named[0].options.isNil:
    return nothing()
  named[0].options(g).scan(g, done[at + 1 .. ^1], typed)

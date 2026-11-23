## Import paths with templates (`nch import ~/fit/bike/{bike}`, `'~/fit/{bike}/*/{}.fit'`): which files a template means,
## and what it caught from each file's path, for the import steps (`tags` makes tags of it).
##
## A template is a path some of whose parts hold `{name}`, `{}` or `*`.  In one part (between two `/`), `{name}` catches
## text that becomes the label `name: TEXT`, `{}` text that becomes a label with no name, and `*` matches text and keeps
## nothing; each is at least one character, and a part may mix them with plain text (`{}.fit`, `2025-*`, `{bike}-{year}`).
## The parts before the first that holds one are the directory searched from (`~` is the home directory).  A template
## whose last part matches a directory means every `.fit` file under it (`walk.nim`), each with what the directory's path
## caught; one whose last part matches a file means that file, if it is a `.fit` file.  Pure but for `expand`.

import std/[algorithm, options, os, strutils]
import ./[channel, walk]

{.push raises: [].}

type
  PieceKind = enum
    pcText ## plain text, matched as it is
    pcStar ## `*`: anything, kept nowhere
    pcHole ## `{name}` or `{}`: anything, kept

  Piece = object
    case kind: PieceKind
    of pcText:
      text: string
    of pcStar:
      discard
    of pcHole:
      key: Option[string]

  PathTemplate* = object ## An import path with `{...}` or `*` in it, read.
    root*: string ## the directory the search starts from
    parts: seq[seq[Piece]] ## each part after it, as its pieces

  Matched* = object ## A file a template means, and what was caught on the way to it.
    path*: string
    labels*: seq[PathLabel]

func isTemplate*(arg: string): bool =
  ## Whether an import path holds a template (`{` or `*`); otherwise it is a file or a directory as it is.
  '{' in arg or '*' in arg

func keyProblem(key: string): Option[string] =
  ## What is wrong with the name of a `{name}`: letters, digits, `-` and `_`.
  if key.len == 0 or key[0] == '-':
    return some("a name in {...} starts with a letter or a digit")
  for c in key:
    if not (c in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '-', '_'} or ord(c) >= 128):
      return some("a name in {...} holds letters, digits, '-' and '_': {" & key & "}")
  none(string)

func piecesOf(part: string): tuple[pieces: seq[Piece], problem: Option[string]] =
  ## The pieces of one part of a template.
  var text = ""
  var i = 0
  template flush() =
    if text.len > 0:
      result.pieces.add Piece(kind: pcText, text: text)
      text = ""

  while i < part.len:
    case part[i]
    of '{':
      let close = part.find('}', i + 1)
      if close < 0:
        return (@[], some("a { is not closed: " & part))
      flush()
      let key = part[i + 1 ..< close]
      if key.len > 0:
        let p = keyProblem(key)
        if p.isSome:
          return (@[], p)
      if result.pieces.len > 0 and result.pieces[^1].kind != pcText:
        return (
          @[],
          some("two of {...} and * with nothing between cannot be told apart: " & part),
        )
      result.pieces.add Piece(
        kind: pcHole, key: (if key.len > 0: some(key) else: none(string))
      )
      i = close + 1
    of '}':
      return (@[], some("a } closes nothing: " & part))
    of '*':
      flush()
      if result.pieces.len > 0 and result.pieces[^1].kind != pcText:
        return (
          @[],
          some("two of {...} and * with nothing between cannot be told apart: " & part),
        )
      result.pieces.add Piece(kind: pcStar)
      inc i
    else:
      text.add part[i]
      inc i
  flush()

proc parseTemplate*(
    arg: string
): tuple[t: Option[PathTemplate], problem: Option[string]] =
  ## The template in an import path, or what is wrong with it.
  let path = expandTilde(arg)
  var root: seq[string]
  var parts: seq[seq[Piece]]
  for part in path.split('/'):
    if parts.len == 0 and not part.isTemplate:
      root.add part
    else:
      if part.len == 0:
        continue # (`a//b`, or a `/` at the end)
      let r = piecesOf(part)
      if r.problem.isSome:
        return (none(PathTemplate), r.problem)
      parts.add r.pieces
  let dir =
    if root.len == 0:
      "."
    elif root.len == 1 and root[0].len == 0:
      "/"
    else:
      root.join("/")
  (some(PathTemplate(root: dir, parts: parts)), none(string))

func matchFrom(
    pieces: seq[Piece], k: int, name: string, at: int, caught: var seq[PathLabel]
): bool =
  ## Whether `pieces[k..]` match `name[at..]`, each hole or star taking as little as it can (and at least a character);
  ## what the holes caught is added to `caught`.
  if k == pieces.len:
    return at == name.len
  let p = pieces[k]
  case p.kind
  of pcText:
    name.continuesWith(p.text, at) and
      matchFrom(pieces, k + 1, name, at + p.text.len, caught)
  of pcStar, pcHole:
    for stop in at + 1 .. name.len:
      var more: seq[PathLabel]
      if matchFrom(pieces, k + 1, name, stop, more):
        if p.kind == pcHole:
          caught.add PathLabel(key: p.key, value: name[at ..< stop])
        caught.add more
        return true
    false

func matchPart*(pieces: seq[Piece], name: string): Option[seq[PathLabel]] =
  ## What one part of a template catches from a name, or none if it does not match.
  var caught: seq[PathLabel]
  if matchFrom(pieces, 0, name, 0, caught):
    some(caught)
  else:
    none(seq[PathLabel])

proc expand*(t: PathTemplate): seq[Matched] {.raises: [OSError].} =
  ## The `.fit` files the template means, in the order of a walk that sorts each directory, each with what was caught.
  proc visit(
      dir: string, k: int, labels: seq[PathLabel], found: var seq[Matched]
  ) {.raises: [OSError].} =
    var entries: seq[tuple[kind: PathComponent, path: string]]
    for e in walkDir(dir):
      entries.add (e.kind, e.path)
    entries.sort do(a, b: tuple[kind: PathComponent, path: string]) -> int:
      cmp(a.path, b.path)
    for (kind, path) in entries:
      let m = matchPart(t.parts[k], path.extractFilename)
      if m.isNone:
        continue
      let here = labels & m.get
      let isDir = kind in {pcDir, pcLinkToDir}
      if k == t.parts.high:
        if isDir:
          for f in fitFiles(path):
            found.add Matched(path: f, labels: here)
        elif path.isFit:
          found.add Matched(path: path, labels: here)
      elif isDir:
        visit(path, k + 1, here, found)

  if t.parts.len == 0 or not dirExists(t.root):
    return
  visit(t.root, 0, @[], result)

## Finding the FIT files under a directory.  Symbolic links are followed, to files and to directories (a folder of links
## to the real files is a way to choose what to import).  A directory is entered once, however many links reach it, so a
## link to a parent (a loop) ends, and a file reached by two routes is one file: the first path in sorted order.  A link
## to a missing file is returned like any other path, so that the import says it cannot be read (not a silent skip).

import std/[algorithm, os, sets, strutils]

{.push raises: [].}

proc isFit(path: string): bool =
  ## Whether the file name ends in `.fit` (any case).
  path.splitFile.ext.toLowerAscii == ".fit"

proc visit(
    dir: string, dirs, files: var HashSet[string], found: var seq[string]
) {.raises: [OSError].} =
  let real = expandFilename(dir)
  if real in dirs:
    return
  dirs.incl real
  var entries: seq[tuple[kind: PathComponent, path: string]]
  for e in walkDir(dir):
    entries.add (e.kind, e.path)
  entries.sort do(a, b: tuple[kind: PathComponent, path: string]) -> int:
    cmp(a.path, b.path)
  for (kind, path) in entries:
    case kind
    of pcFile, pcLinkToFile:
      if path.isFit:
        let target =
          try:
            expandFilename(path)
          except OSError:
            path # (a broken link: the import reports it)
        if target notin files:
          files.incl target
          found.add path
    of pcDir, pcLinkToDir:
      visit(path, dirs, files, found)

proc fitFiles*(root: string): seq[string] {.raises: [OSError].} =
  ## The `.fit` files under the directory, links followed, each once, in the order of a walk that sorts each directory.
  var dirs, files: HashSet[string]
  visit(root, dirs, files, result)

## Reading the `import` lines of source files and checking them against the rules about packages
## (dev/PACKAGES.md, "Layout and rules" 4).  Pure: the files are given as text, so the rules are tested with
## made-up trees, and the real tree is checked by tests/core/test_imports.nim.
##
## Only imports that start a line are read (an import inside `when` is of the standard library today), and
## only a module that exists as a file under `src/nimchoo` counts as ours; any other is the standard or a
## third-party library, which anything may import.

import std/[algorithm, os, sequtils, sets, strutils, tables]

type Violation* = object
  file*: string ## relative to `src/nimchoo`
  imports*: string ## the file it imports, relative to `src/nimchoo`
  why*: string

func withoutComments(text: string): string =
  ## `#[ ... ]#` and `# ...` removed (an import line has no `#` in a string).
  var i = 0
  var depth = 0
  while i < text.len:
    if text.continuesWith("#[", i):
      inc depth
      i += 2
    elif depth > 0 and text.continuesWith("]#", i):
      dec depth
      i += 2
    elif depth > 0:
      inc i
    elif text[i] == '#':
      while i < text.len and text[i] != '\n':
        inc i
    else:
      result.add text[i]
      inc i

func expand(spec: string): seq[string] =
  ## `a/[b, c], d as e, f except g` -> `a/b`, `a/c`, `d`, `f`.
  var s = spec
  if " except " in s:
    s = s.split(" except ")[0]
  var current = ""
  var depth = 0
  var items: seq[string]
  for c in s:
    if c == '[':
      inc depth
    elif c == ']':
      dec depth
    if c == ',' and depth == 0:
      items.add current
      current = ""
    else:
      current.add c
  items.add current
  for item in items:
    let it = item.splitWhitespace.join(" ")
    let open = it.find('[')
    if open >= 0:
      let prefix = it[0 ..< open]
      for part in it[open + 1 ..< it.rfind(']')].split(','):
        let name = part.strip.split(" as ")[0].strip
        if name.len > 0:
          result.add prefix & name
    elif it.len > 0:
      result.add it.split(" as ")[0].strip

func importedNames*(text: string): seq[string] =
  ## The modules a source text imports, as written (`../db/store`, `std/os`), in order.  Handles
  ## `import a, b`, `import a/[b, c]`, lists over several lines, `as`, `except`, and `from a import b`.
  let lines = text.withoutComments.splitLines
  var i = 0
  while i < lines.len:
    let line = lines[i]
    inc i
    if line.startsWith("import ") or line == "import":
      var statement = line["import".len ..^ 1]
      while i < lines.len and lines[i].len > 0 and lines[i][0] in {' ', '\t'}:
        statement.add " " & lines[i]
        inc i
      result.add expand(statement)
    elif line.startsWith("from ") and " import " in line:
      result.add line["from ".len ..^ 1].split(" import ")[0].strip

func resolve*(file, name: string, files: HashSet[string]): string =
  ## The file `name` (as written in `file`) is, relative to `src/nimchoo`; "" if it is not a file of ours.
  let target =
    if name.startsWith("nimchoo/"):
      name["nimchoo/".len ..^ 1]
    else:
      normalizedPath(file.parentDir / name)
  if target.startsWith("..") or target.startsWith("/"):
    return ""
  let path = target & ".nim"
  if path in files: path else: ""

func packageOf*(path: string, files: HashSet[string]): string =
  ## The directory of the package that holds `path` (the nearest directory above it with a `package.nim`),
  ## relative to `src/nimchoo`; "" if none.
  var dir = path.parentDir
  while dir.len > 0:
    if dir / "package.nim" in files:
      return dir
    dir = dir.parentDir

func isCore(path: string): bool =
  path.startsWith("core/")

func violations*(
    sources: Table[string, string], depends: Table[string, seq[string]]
): seq[Violation] =
  ## The imports that break the rules.  `sources` maps each file under `src/nimchoo` (relative path) to its
  ## text; `depends` maps a package name to the packages it declares.  A file in a package may import its own
  ## package, `core`, and the packages it depends on; a file in `core` imports no package.  Files in neither
  ## are not checked, and a package may not import them.
  var files: HashSet[string]
  for path in sources.keys:
    files.incl path
  for path in sorted(toSeq(sources.keys)):
    let own = packageOf(path, files)
    if own.len == 0 and not path.isCore:
      continue
    for name in importedNames(sources[path]):
      let target = resolve(path, name, files)
      if target.len == 0 or target.isCore:
        continue
      let other = packageOf(target, files)
      if other.len == 0:
        result.add Violation(
          file: path, imports: target, why: "is not in a package or in core"
        )
      elif path.isCore:
        result.add Violation(
          file: path,
          imports: target,
          why: "core imports no package (it is in '" & other.lastPathPart & "')",
        )
      elif other != own and
          other.lastPathPart notin depends.getOrDefault(own.lastPathPart):
        result.add Violation(
          file: path,
          imports: target,
          why:
            "'" & own.lastPathPart & "' does not declare a dependency on '" &
            other.lastPathPart & "'",
        )

func rawDatabaseImports*(sources: Table[string, string]): seq[string] =
  ## The files that import the database library (`db_connector/...`) and are neither in the package `db` nor in
  ## `core` (whose `Fragment` has to name the connection type): every statement is to go through the checked
  ## helpers of `db` (dev/REVIEW.md 4.2), and `db` re-exports the types it hands out.
  for path in sorted(toSeq(sources.keys)):
    if path.startsWith("packages/db/") or path.isCore:
      continue
    if importedNames(sources[path]).anyIt(it.startsWith("db_connector")):
      result.add path

func namesTable(text, table: string): bool =
  ## Whether `text` has SQL that names `table`: `from`, `join`, `into`, `update` or `references` before it (a word
  ## of its own).  Lenient: an English "from file" counts too, which can only let an unused dependency through.
  let lower = text.toLowerAscii
  for kw in ["from", "join", "into", "update", "references"]:
    var at = 0
    while true:
      at = lower.find(kw, at)
      if at < 0:
        break
      let before = at == 0 or lower[at - 1] notin IdentChars
      var i = at + kw.len
      if before and i < lower.len and lower[i] in Whitespace:
        while i < lower.len and lower[i] in Whitespace:
          inc i
        if lower.continuesWith(table, i) and
            (i + table.len >= lower.len or lower[i + table.len] notin IdentChars):
          return true
      at += kw.len
  false

func unusedDepends*(
    sources: Table[string, string],
    depends: Table[string, seq[string]],
    tables: Table[string, seq[string]],
): seq[string] =
  ## The dependencies a package declares and does not use, as "package -> dependency": it neither imports a file of
  ## the dependency nor has SQL that names one of its tables (`tables`: package -> the tables it owns).  `sources`
  ## maps each file under `src/nimchoo` (the `.nim` files and the fragments, `.sql`) to its text.
  var files: HashSet[string]
  for path in sources.keys:
    files.incl path
  var dirOf: Table[string, string] # package name -> its directory
  for path in files:
    if path.extractFilename == "package.nim":
      dirOf[path.parentDir.lastPathPart] = path.parentDir
  for name in sorted(toSeq(depends.keys)):
    let own = dirOf.getOrDefault(name)
    var imported: HashSet[string]
    var text = ""
    for path in files:
      if packageOf(path, files) != own or path.extractFilename == "package.nim":
        continue
      text.add sources[path] & "\n"
      if path.endsWith(".nim"):
        for n in importedNames(sources[path]):
          let target = resolve(path, n, files)
          if target.len > 0:
            imported.incl packageOf(target, files)
    for d in depends[name]:
      let used =
        dirOf.getOrDefault(d) in imported or
        tables.getOrDefault(d).anyIt(text.namesTable(it))
      if not used:
        result.add name & " -> " & d

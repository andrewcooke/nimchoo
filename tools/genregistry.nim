## Writes `src/nimchoo/registry.nim`: the list of the packages found under `src/nimchoo/packages/`.  Run by
## the nimble tasks (`nimble registry`), because Nim does not notice a new directory by itself.  A test
## makes the text again and compares it with the file, so a stale registry fails the tests.
##
## A package is a directory that holds `package.nim`; its name is the name of that directory.  Here are
## only the checks of the layout (no package inside another, no name twice, a `##` comment that documents the
## package at the top of its package.nim); the dependencies are checked by `core/registry.nim` when the registry
## is compiled.
##
## The `##` comment is the documentation of the package, written once: `nim doc` makes its page, this generator puts
## its text in the registry (`nch packages` shows it) and writes the front page of the documentation, which lists the
## packages with the first line of each.

import std/[algorithm, os, sequtils, strutils]

const maxSummary* = 100 ## the longest first line of a package's documentation

type Found* = object ## a package directory, found on disk
  name*: string
  importPath*: string ## from `src/nimchoo`, without `.nim`: "packages/text/fold/package"
  doc*: string ## the `##` comment at the top of package.nim, without the marks

func docOf*(text: string): string =
  ## The `##` comment at the top of a source file, without the marks (and the one space after them): "" if there is
  ## none.  Blank lines before it are skipped; it ends at the first line that does not start with `##`.
  var started = false
  var lines: seq[string]
  for line in text.splitLines:
    if line.startsWith("##"):
      started = true
      let rest = line[2 .. ^1]
      lines.add (if rest.startsWith(" "): rest[1 .. ^1] else: rest)
    elif started or line.strip.len > 0:
      break
  result = lines.join("\n").strip(chars = {'\n', ' '})

func summaryOf*(doc: string): string =
  ## The first line of the documentation.
  doc.splitLines[0].strip

func undocumented*(name, path: string): string =
  ## The message for a package.nim without documentation: what to do, with an example, so that adding a package is easy.
  "package '" & name & "' has no documentation: " & path & """
 must start with a `##` comment that says what the package is.

Every package describes itself at the top of its package.nim.  The first line is a one-line summary (up to """ &
    $maxSummary & """
characters: `nch packages` shows it, and so does the list of packages on the documentation site); the lines
after it say what the package is for, what it owns (tables, commands, extension points) and its rules, in a few short
paragraphs.  Documentation comments are RST: put code in backquotes.  For example, at the very top of the file:

    ## What `""" &
    name & """` is for, in one line.
    ##
    ## A paragraph or two: what it owns, how other packages use it, and any rule that
    ## the code does not make obvious.

    import ../../core/manifest
    const package* = Package(depends: @[], fragments: @[])

(Any other package.nim is a model, for example src/nimchoo/packages/text/fold/package.nim.)"""

func summaryTooLong*(name, path: string, summary: string): string =
  ## The message for a first line that is too long to be a summary.
  "the first line of the `##` comment in " & path & " (package '" & name & "') is " &
    $summary.len & " characters, and a summary is at most " & $maxSummary &
    ": it is shown in lists of packages.\nKeep the first line to one short sentence, then a blank `##` line, then the rest of the documentation."

proc findPackages*(
    root: string
): seq[Found] {.raises: [OSError, ValueError, IOError].} =
  ## The packages under `root` (the `packages` directory), sorted by import path.
  var dirs: seq[string]
  for path in walkDirRec(root, yieldFilter = {pcFile}, relative = true):
    if path.lastPathPart == "package.nim":
      dirs.add path.parentDir
  dirs.sort
  for i, d in dirs:
    for other in dirs[0 ..< i]:
      if d.startsWith(other & "/"):
        raise newException(
          ValueError, "package '" & other & "' contains the package '" & d & "'"
        )
    let name = d.lastPathPart
    if name.len == 0 or not name.allIt(it in IdentChars) or name[0] notin IdentStartChars:
      raise newException(
        ValueError, "'" & name & "' cannot be a package name (letters, digits, _)"
      )
    let path = root / d / "package.nim"
    let doc = docOf(readFile(path))
    if doc.len == 0:
      raise newException(ValueError, undocumented(name, path))
    if summaryOf(doc).len > maxSummary:
      raise newException(ValueError, summaryTooLong(name, path, summaryOf(doc)))
    if "\"\"\"" in doc:
      raise newException(
        ValueError,
        "the documentation in " & path &
          " holds three double quotes in a row, which the registry cannot carry",
      )
    result.add Found(name: name, importPath: "packages" / d / "package", doc: doc)

func nimString(s: string): string =
  ## `s` as a Nim string literal on one line.
  "\"" & s.replace("\\", "\\\\").replace("\"", "\\\"") & "\""

const maxLine = 88 ## nph breaks a line that is longer

func field(name, value: string): string =
  ## `      name: value,` as nph writes it: on the next line when the first line is too long (so that `nimble fmtcheck`
  ## has nothing to say about the registry, which is checked in).
  let first = value.splitLines[0]
  if ("      " & name & ": " & first & ",").len > maxLine:
    "      " & name & ":\n        " & value & ",\n"
  else:
    "      " & name & ": " & value & ",\n"

func registryText*(found: seq[Found]): string =
  ## The text of `registry.nim` for these packages: the front page of the documentation (the `##` comment that
  ## `nim doc` makes the page of the registry from), then the list of the packages.
  result =
    "# GENERATED by `nimble registry` (tools/genregistry.nim): do not edit.  The packages, each after the\n"
  result.add "# packages it depends on; the checks of the dependencies are made when this is compiled.\n\n"
  result.add "## The packages of nimchoo and what each is for: the first line of the documentation at the top of its\n"
  result.add "## package.nim (click a name for the rest).  `nch packages` says the same in a terminal, with the dependencies\n"
  result.add "## (`nch packages --graph` draws them by layer).  The code that every package may use is in `core`.\n##\n"
  for f in found.sortedByIt(it.name):
    result.add "## * `" & f.name & " <" & f.importPath & ".html>`_ - " & summaryOf(
      f.doc
    ) & "\n"
  result.add "\nimport ./core/[access, errors, extension, fragment, manifest]\nimport ./core/registry as coreRegistry\nimport ./packages/db/store as dbStore\n"
  for f in found:
    result.add "import ./" & f.importPath & " as pkg" & f.name.capitalizeAscii & "\n"
  result.add "\nconst packages*: seq[Registered] = inDependencyOrder(\n  @[\n"
  for f in found:
    result.add "    Registered(\n      name: \"" & f.name & "\",\n      package: pkg" &
      f.name.capitalizeAscii & ".package,\n"
    result.add field("summary", nimString(summaryOf(f.doc)))
    result.add field("doc", "\"\"\"" & f.doc & "\"\"\"")
    result.add "    ),\n"
  result.add "  ]\n)\n"
  result.add "\nconst commands*: seq[CommandDecl] = collectCommands(packages)\n"
  result.add "\nconst points*: seq[tuple[owner: string, point: PointDecl]] = collectPoints(packages)\n  ## the extension points the packages define\n"
  result.add "\nconst allFragments*: seq[Fragment] = collectFragments(packages)\n  ## the schema: every package's fragments, in dependency order (after the database's own, `db/001-schema.sql`)\n"
  result.add "\nconst schema*: seq[Fragment] = baseFragments & allFragments\n  ## every fragment, the database's own first\n"
  result.add "\nproc newAllAccess*(mode: AccessMode): Access =\n  ## The access rules for all the packages, in this `mode`.\n  try:\n    result = accessOf(packages, baseFragments & allFragments, mode)\n  except PackageError as e:\n    raiseAssert e.msg\n\nlet allAccess*: Access = newAllAccess(amEnforce)\n  ## the rules `nch` and the tests run under\n"
  result.add "\nlet extensions*: Extensions = collectExtensions(packages)\n  ## what the packages contribute to each other (made when `nch` starts)\n"

when isMainModule:
  let source = currentSourcePath().parentDir.parentDir / "src" / "nimchoo"
  try:
    writeFile(source / "registry.nim", registryText(findPackages(source / "packages")))
  except CatchableError as e:
    stderr.writeLine "genregistry: " & e.msg
    quit 1

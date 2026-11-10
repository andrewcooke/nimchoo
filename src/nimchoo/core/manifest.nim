## What a package says about itself.  `package.nim` in a package's directory holds one constant of this
## type; the name of the package is the name of its directory, so it is not in the value (PACKAGES.md).
## This module imports no package: `core` is below all of them.

import ./[extension, fragment, globals]
export fragment

{.push raises: [].}

type
  ContributeProc* = proc(): seq[Contribution] {.nimcall, raises: [].}

  CommandProc* = proc(g: Globals, args: seq[string]): int {.nimcall, raises: [].}
    ## A command: given the options before its name and its own arguments, it returns the exit status.

  CommandDecl* = object ## a command that a package provides
    name*: string ## what the user types after `nch`
    summary*: string ## one line, for the usage text
    run*: CommandProc

  PointDecl* = object
    ## An extension point a package defines (`core/extension.nim`), so that it can be listed even with no contributor.
    name*: string
      ## the point's name: `point.name`, which starts with the package's: "importer/after"
    summary*: string ## one line: what packages may add through it

  Package* = object
    depends*: seq[string] ## the packages whose code and tables it uses, by name
    fragments*: seq[Fragment] ## its DDL, in order
    commands*: seq[CommandDecl]
      ## the commands it provides (only command packages have any)
    defines*: seq[PointDecl]
      ## the extension points it defines, which other packages contribute to (the registry refuses a contribution
      ## to a point nobody defines)
    contributes*: ContributeProc
      ## what it offers to the extension points of packages below it; nil: nothing.  A proc, because the
      ## values (a step with procs in it) are made at run time, while `package` is a constant

  Registered* = object ## a package with its name, as the generated registry lists them
    name*: string
    package*: Package
    summary*: string ## the first line of the `##` comment of its package.nim
    doc*: string
      ## the whole `##` comment: what the package is for (the generator reads it from the file)

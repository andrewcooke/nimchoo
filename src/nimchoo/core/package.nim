## What a package says about itself.  `package.nim` in a package's directory holds one constant of this
## type; the name of the package is the name of its directory, so it is not in the value (PACKAGES.md).
## This module imports no package: `core` is below all of them.

import ./fragment

{.push raises: [].}

type
  Package* = object
    depends*: seq[string] ## the packages whose code and tables it uses, by name
    fragments*: seq[Fragment] ## its DDL, in order

  Registered* = object ## a package with its name, as the generated registry lists them
    name*: string
    package*: Package

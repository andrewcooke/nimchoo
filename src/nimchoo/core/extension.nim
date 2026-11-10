## Extension points: where a low package calls code that a higher package supplies (PACKAGES.md, "Extension
## points").  The package that defines a point owns its type and declares the point as a constant; a later
## package lists a contribution in its `package.nim`.  `core` knows no domain type, so a contribution holds
## its value type-erased; `get` gives the typed list back.
##
## All in memory: the registry collects the contributions when `nch` starts and `nch` puts them in `Globals`.
## Nothing here touches the database or the disk.

import std/[algorithm, tables]

{.push raises: [].}

type
  ExtensionPoint*[T] = object
    ## A place that packages can contribute values of type `T` to.
    name*: string ## unique among points: say the package, `"importer/steps"`

  Contribution* = ref object of RootObj
    ## One value offered to a point, its type erased (see `contribute`).
    point*: string
    typeName*: string ## `$T`, to notice two points that share a name but not a type
    priority*: int ## lower first; equal priorities keep dependency order
    source*: string ## the package that made it (the registry puts it in)

  Boxed[T] = ref object of Contribution
    value: T

  Extensions* = object ## What the packages contributed, by the name of the point.
    byPoint: Table[string, seq[Contribution]]

func contribute*[T](point: ExtensionPoint[T], value: T, priority = 0): Contribution =
  ## Offer `value` to `point`.  The type is checked here, by the compiler.
  Boxed[T](point: point.name, typeName: $T, priority: priority, value: value)

func add*(e: var Extensions, c: Contribution) =
  ## Add a contribution.  The registry calls this in dependency order.
  e.byPoint.mgetOrPut(c.point, @[]).add c

func get*[T](e: Extensions, point: ExtensionPoint[T]): seq[T] =
  ## The values contributed to `point`: by priority, then in the order they were added (dependency order).
  ## Two points of one name but different types are a bug (the registry refuses them when it is built).
  let all = e.byPoint.getOrDefault(point.name)
  for c in all.sortedByIt(it.priority): # (stable)
    doAssert c of Boxed[T], "extension point '" & point.name & "' holds a " & c.typeName
    result.add Boxed[T](c).value

func points*(e: Extensions): seq[string] =
  ## The names of the points that have contributions, in order.
  for name in e.byPoint.keys:
    result.add name
  result.sort

func contributions*(e: Extensions, point: string): seq[Contribution] =
  ## What was contributed to the point, in the order `get` gives it: by priority, then in dependency order.
  result = e.byPoint.getOrDefault(point).sortedByIt(it.priority) # (stable)

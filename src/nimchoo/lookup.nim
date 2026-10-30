## Table lookups that have to succeed.
##
## `t[key]` raises KeyError, which would have to be handled (or declared in
## every `{.raises.}` list) even where the key has just been checked or is
## guaranteed by construction.  A missing key there is a bug in nimchoo, not
## bad input, so these raise an AssertionDefect instead (a Defect: never
## caught, never a warning, and invisible to `{.raises.}`).

import std/tables

func must*[K, V](t: Table[K, V], key: K): lent V =
  ## `t[key]`, for a key that has to be there.
  doAssert key in t, "internal error: missing key " & $key
  {.cast(raises: []).}:  # just checked
    t[key]

func mustMut*[K, V](t: var Table[K, V], key: K): var V =
  ## `t[key]` for modifying the value, for a key that has to be there.
  doAssert key in t, "internal error: missing key " & $key
  {.cast(raises: []).}:  # just checked
    t[key]

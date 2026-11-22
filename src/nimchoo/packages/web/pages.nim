## What the commands with web pages share for making their files: making the cache directories,
## and escaping text for a page (re-exported from packages/text/templating).

import std/os
import ../../core/globals
import ../bundle/unpack
import ../cache/cache
import ../text/templating/templating
export templating.htmlEscape

{.push raises: [].}

proc cannotWrite*(g: Globals, command, dir: string): int =
  ## A failure to write in the cache (or to make its directories), as the current exception says: the one message of every page
  ## command.
  failure(g, command, "cannot write to " & dir & ": " & getCurrentExceptionMsg())

proc templateFailure*(g: Globals, command, msg: string): int =
  ## A page that cannot be made from its template, said the one way (the templates and the libraries are the user's to edit).
  failure(
    g,
    command,
    "cannot make the page: " & msg &
      " (the templates are in system/templates/ and the libraries are system/libraries.cdn, in the cache directory; delete one to have the built-in one again)",
  )

proc makeCacheDirs*(dir: string) {.raises: [IOError, OSError].} =
  ## The cache directory and its two parts, if they are not there (and the licence notice in `system/`).
  createDir userDir(dir)
  createDir systemDir(dir)
  unpackNotice(dir)

## What the commands with web pages share for making their files: making the cache directories,
## and escaping text for a page (re-exported from packages/text/templating).

import std/os
import ../bundle/unpack
import ../cache/cache
import ../text/templating/templating
export templating.htmlEscape

{.push raises: [].}

proc makeCacheDirs*(dir: string) {.raises: [IOError, OSError].} =
  ## The cache directory and its two parts, if they are not there (and the licence notice in `system/`).
  createDir userDir(dir)
  createDir systemDir(dir)
  unpackNotice(dir)

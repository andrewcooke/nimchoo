## What the commands with web pages share for making their files: making the cache directories,
## escaping text for a page (re-exported from templating.nim), and writing a file so that nobody sees
## half of it.

import std/os
import ../bundle/unpack
import ../cache
import ../templating
export templating.htmlEscape

{.push raises: [].}

proc makeCacheDirs*(dir: string) {.raises: [IOError, OSError].} =
  ## The cache directory and its two parts, if they are not there (and the licence notice in `system/`).
  createDir userDir(dir)
  createDir systemDir(dir)
  unpackNotice(dir)

proc writeAtomic*(path, text: string) {.raises: [IOError, OSError].} =
  ## Write the file so that nobody sees half of it: to a new name, then rename.
  createDir parentDir(path)
  let tmp = path & ".part"
  writeFile(tmp, text)
  try:
    moveFile(tmp, path)
  except OSError as e:
    raise e
  except Exception:              # (moveFile is declared to raise anything)
    raise newException(OSError, "cannot rename " & tmp)

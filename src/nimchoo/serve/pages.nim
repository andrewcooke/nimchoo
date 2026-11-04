## What the commands with web pages share for making their files: filling in a page template,
## escaping text for a page, and writing a file so that nobody sees half of it.

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

func replaceAll*(s, key, value: string): string =
  ## `s` with each occurrence of `key` replaced by `value` (no regex, no surprises).
  var i = 0
  while i < s.len:
    if i + key.len <= s.len and s[i ..< i + key.len] == key:
      result.add value
      i += key.len
    else:
      result.add s[i]
      inc i

func fill*(template1: string, values: openArray[(string, string)]): string =
  ## The template with each `@NAME@` replaced by its value.
  result = template1
  for (k, v) in values: result = result.replaceAll("@" & k & "@", v)

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

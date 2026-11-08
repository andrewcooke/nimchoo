## Writing a file so that nobody ever sees half of it: the one way the program does it.  The text goes to a file of
## its own (a name no other process or thread uses), which is then renamed over the target; a rename within one
## directory is a single step.  A fixed temporary name (`file.part`) would be shared by two writers of the same file,
## and one could rename the other's half-written text, or find it gone.

import std/[monotimes, os]

{.push raises: [].}

proc tempNameFor(path: string): string =
  ## A name beside `path` that only this call uses: the process, and the moment (to the nanosecond).
  path & "." & $getCurrentProcessId() & "-" & $getMonoTime().ticks & ".part"

proc dropTemp(tmp: string) =
  try:
    removeFile(tmp)
  except OSError:
    discard

proc writeAtomic*(path, text: string) {.raises: [IOError, OSError].} =
  ## Write the file at `path` (its directory is made if it is not there) so that it is either as it was or whole.
  ## The temporary file does not stay if anything fails.
  createDir parentDir(path)
  let tmp = tempNameFor(path)
  try:
    writeFile(tmp, text)
  except IOError as e:
    dropTemp(tmp)
    raise e
  try:
    moveFile(tmp, path)
  except OSError as e:
    dropTemp(tmp)
    raise e
  except Exception: # (moveFile is declared to raise anything)
    dropTemp(tmp)
    raise newException(OSError, "cannot rename " & tmp & " to " & path)

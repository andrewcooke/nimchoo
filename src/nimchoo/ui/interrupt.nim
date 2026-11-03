## Ctrl-C for commands that run until they are stopped (a server): print a newline and
## stop with the conventional status 130.  (`quit` inside a signal handler ends with
## status 127, hence `exitnow`.)

when defined(posix):
  import std/posix

{.push raises: [].}

proc stopOnInterrupt() {.noconv.} =
  try: stderr.write "\n"
  except IOError: discard
  when defined(posix):
    exitnow(130)
  else:
    quit(130)

proc exitOnInterrupt*() =
  ## From now on Ctrl-C stops the program with status 130.
  setControlCHook(stopOnInterrupt)

## What `nch --version` says: the number in nimchoo.nimble and the git commit the
## program was built from, found when it is compiled.
##
## The commit is found when this module is compiled, and Nim does not compile a
## module again because the repository moved on.  So `nimble prod` looks the commit up
## itself and hands it over as `-d:nchCommit=HASH` (and `-d:nchDirty` if there are
## uncommitted changes): then only this module changes between builds, and the rest
## comes from Nim's cache (about 4 to 6 seconds for a typical edit, not 18).  A build
## without those defines (the tests, `nim c` by hand) looks the commit up here, as before.

import std/[os, strutils]

{.push raises: [].}

func versionFromNimble*(text: string): string =
  ## The value of the `version = "..."` line, or "unknown".
  for line in text.splitLines:
    let l = line.strip
    if l.startsWith("version") and '"' in l:
      let first = l.find('"')
      let last = l.rfind('"')
      if last > first: return l[first + 1 ..< last]
  "unknown"

func commitText*(hash: string, dirty: bool): string =
  ## "a1b2c3d", "a1b2c3d-dirty", or "unknown" if there is no hash (not built from a git checkout).
  if hash.len == 0: "unknown"
  elif dirty: hash & "-dirty"
  else: hash

func versionLine*(version, commit: string): string =
  "nch " & version & " (" & commit & ")"

const
  givenCommit {.strdefine: "nchCommit".} = ""        ## from the build task: the short commit hash
  givenDirty {.booldefine: "nchDirty".} = false      ## ... and whether there were uncommitted changes
  sourceDir = currentSourcePath().parentDir
  repoDir = sourceDir.parentDir.parentDir
  nimbleText = staticRead(repoDir / "nimchoo.nimble")
  hashed = gorgeEx("git -C " & quoteShell(repoDir) & " rev-parse --short HEAD")
  changes = gorgeEx("git -C " & quoteShell(repoDir) &
                    " status --porcelain --untracked-files=no")

const
  nchVersion* = versionFromNimble(nimbleText)
  nchCommit* =
    if givenCommit.len > 0: commitText(givenCommit, givenDirty)
    else: commitText(if hashed.exitCode == 0: hashed.output.strip else: "",
                     changes.exitCode == 0 and changes.output.strip.len > 0)

const versionString* = versionLine(nchVersion, nchCommit)

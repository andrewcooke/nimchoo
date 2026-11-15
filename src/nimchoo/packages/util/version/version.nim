## What `nch --version` says: the number in nimchoo.nimble and the git commit the
## program was built from, found when it is compiled; and `nchBuild`, which tells builds apart.
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
      if last > first:
        return l[first + 1 ..< last]
  "unknown"

func commitText*(hash: string, dirty: bool): string =
  ## "a1b2c3d", "a1b2c3d-dirty", or "unknown" if there is no hash (not built from a git checkout).
  if hash.len == 0:
    "unknown"
  elif dirty:
    hash & "-dirty"
  else:
    hash

func versionLine*(version, commit: string): string =
  ## "nch 0.1 (abc1234)".
  "nch " & version & " (" & commit & ")"

proc repoRoot(start: string): string =
  ## The directory above `start` that holds `nimchoo.nimble` (so that moving this package changes nothing).
  result = start
  while not fileExists(result / "nimchoo.nimble"):
    let up = result.parentDir
    doAssert up != result, "nimchoo.nimble not found above " & start
    result = up

const
  givenCommit {.strdefine: "nchCommit".} = ""
    ## from the build task: the short commit hash
  givenDirty {.booldefine: "nchDirty".} = false
    ## ... and whether there were uncommitted changes
  givenBuilt {.strdefine: "nchBuilt".} = ""
    ## ... and the time of the build (seconds since 1970)
  sourceDir = currentSourcePath().parentDir
  repoDir = repoRoot(sourceDir)
  nimbleText = staticRead(repoDir / "nimchoo.nimble")
  hashed = gorgeEx("git -C " & quoteShell(repoDir) & " rev-parse --short HEAD")
  changes = gorgeEx(
    "git -C " & quoteShell(repoDir) & " status --porcelain --untracked-files=no"
  )

const
  nchVersion* = versionFromNimble(nimbleText)
  nchCommit* =
    if givenCommit.len > 0:
      commitText(givenCommit, givenDirty)
    else:
      commitText(
        if hashed.exitCode == 0: hashed.output.strip else: "",
        changes.exitCode == 0 and changes.output.strip.len > 0,
      )

const versionString* = versionLine(nchVersion, nchCommit)

const nchBuild* =
  nchCommit & " " & (
    if givenBuilt.len > 0:
      givenBuilt
    else:
      CompileDate & "T" & CompileTime
  )
  ## What tells one build of the program from another, for a key of something it made (`subject/keys`): the commit, and the
  ## time of the build, so that a build of uncommitted changes is not taken for the build of the commit before them.  The
  ## tasks that build the program give the time (a module that Nim does not compile again would keep an old one).

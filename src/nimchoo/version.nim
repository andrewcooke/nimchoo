## What `nch --version` says: the number in nimchoo.nimble and the git commit the
## program was built from, found when it is compiled.
##
## The commit is only looked up when this module is compiled, and Nim does not
## compile a module again because the repository moved on, so a build that
## should say the right thing has to be forced (`nimble prod` does that).

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
  sourceDir = currentSourcePath().parentDir
  repoDir = sourceDir.parentDir.parentDir
  nimbleText = staticRead(repoDir / "nimchoo.nimble")
  hashed = gorgeEx("git -C " & quoteShell(repoDir) & " rev-parse --short HEAD")
  changes = gorgeEx("git -C " & quoteShell(repoDir) &
                    " status --porcelain --untracked-files=no")

const
  nchVersion* = versionFromNimble(nimbleText)
  nchCommit* = commitText(if hashed.exitCode == 0: hashed.output.strip else: "",
                          changes.exitCode == 0 and changes.output.strip.len > 0)

const versionString* = versionLine(nchVersion, nchCommit)

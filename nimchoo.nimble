# Package

version       = "0.1.0"
author        = "andrew cooke"
description   = "lightweight tools for fitness data (rework of choochoo)"
license       = "MIT"
srcDir        = "src"
bin           = @["nimchoo"]

# Dependencies

requires "nim >= 2.2.0"
requires "xl"
requires "zippy >= 0.10.4"

task test, "Run all tests":
  exec "nim c -r --hints:off tests/all.nim"

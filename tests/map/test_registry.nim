## The frames and subjects of the real registry (what no one package can check about the others): every frame is of a subject
## that exists, a frame's name is its own within the subject, and each style and drawing can go in a page.

import std/[json, options, sequtils, unittest]
import nimchoo/core/extension
import nimchoo/packages/map/[frames, page]
import nimchoo/packages/subject/subjects
from nimchoo/registry import extensions

suite "map: the registry of frames":
  test "every frame is of a subject that is registered":
    let names = extensions.get(subjectPoint).mapIt(it.name)
    check names.len > 0
    for f in extensions.get(mapFramePoint):
      check f.subject in names

  test "a frame's name is its own within its subject":
    let all = extensions.get(mapFramePoint)
    check all.len > 0
    for f in all:
      check framesOf(all, f.subject).countIt(it.name == f.name) == 1

  test "every frame's style has what its drawing reads, and its drawing can go in a page":
    for f in extensions.get(mapFramePoint):
      check frameStyle(f).kind == JObject
      if f.script.isSome:
        check drawerText(f.script.get).len > 0

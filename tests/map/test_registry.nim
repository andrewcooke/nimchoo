## The frames and subjects of the real registry (what no one package can check about the others): every frame is of a subject
## that exists, a frame's name is its own within the subject, and the styles of the frames share no group.

import std/[sequtils, unittest]
import nimchoo/core/[errors, extension]
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

  test "the styles of the frames share no group (one would replace the other)":
    discard joinedStyle(paletteValues(), extensions.get(mapFramePoint))

  test "two styles with the same group are refused, naming both":
    var all = extensions.get(mapFramePoint)
    check all.len >= 1
    all.add all[0] # (the same frame twice: every group of its style is there twice)
    expect TemplateError:
      discard joinedStyle(paletteValues(), all)

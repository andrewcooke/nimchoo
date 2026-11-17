## The files of a map are named by what they were made from (`map-activities-routes-3f9a0c1d5e7b2a46.geojson`): helpers to find them
## and to compare names without the key.

import std/[algorithm, os, strutils, times]

const keyLen = 16 ## hex digits

func isKey(s: string): bool =
  s.len == keyLen and s.allCharsInSet({'0' .. '9', 'a' .. 'f'})

func unkeyed*(name: string): string =
  ## "map-activities-routes-3f9a0c1d5e7b2a46.geojson" is "map-activities-routes.geojson"; a name with no key is as it is.
  let (_, base, ext) = splitFile(name)
  let dash = base.rfind('-')
  if dash >= 0 and isKey(base[dash + 1 .. ^1]):
    base[0 ..< dash] & ext
  else:
    name

func unkeyed*(names: seq[string]): seq[string] =
  ## Each without its key, in order.
  result = @[]
  for n in names:
    result.add unkeyed(n)
  result.sort

proc keyedFile*(cache, stem, ext: string): string =
  ## The newest file `stem-KEY.ext` of the directory (the path); "" if there is none.
  var newest: Time
  if dirExists(cache):
    for path in walkFiles(cache / (stem & "-*." & ext)):
      let name = extractFilename(path)
      if unkeyed(name) == stem & "." & ext:
        let t = getLastModificationTime(path)
        if result.len == 0 or t > newest:
          result = path
          newest = t

proc keyedNameIn*(text, stem, ext: string): string =
  ## The name `stem-KEY.ext` that a text (a page) holds; "" if it holds none.
  let at = text.find(stem & "-")
  if at < 0:
    return ""
  let name = text[at ..< min(text.len, at + stem.len + 1 + keyLen + 1 + ext.len)]
  if unkeyed(name) == stem & "." & ext: name else: ""

proc forget*(cache: string) =
  ## Delete the files of the directory, so that what is made next is the only file (two files made within the same
  ## instant cannot be told apart by their times).
  removeDir(cache)

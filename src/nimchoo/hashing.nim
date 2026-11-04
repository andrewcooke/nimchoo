## SHA-256 as the hex text the program uses wherever something is named by its content: files,
## fragments of the schema, selections, the data impulses are made from, bundled files.

import std/strutils
import checksums/sha2

{.push raises: [].}

func sha256Hex*(text: string): string =
  ## The SHA-256 of a text, as 64 lower-case hex digits.
  for c in secureHash(Sha_256, text):
    result.add toLowerAscii(toHex(ord(c), 2))

func sha256Hex*(data: openArray[byte]): string =
  ## ... of bytes.
  var text = newString(data.len)
  for i, b in data: text[i] = char(b)
  sha256Hex(text)

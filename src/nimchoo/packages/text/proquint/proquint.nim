## Numbers as pronounceable words (proquints, https://arxiv.org/html/0901.4016): each 16 bits are five letters, consonant
## vowel consonant vowel consonant, 4 + 2 + 4 + 2 + 4 bits, groups joined by hyphens: the 32 bits of 127.0.0.1 are
## "lusab-babad".  Decodable, unlike a hash.  Pure.

import std/options

{.push raises: [].}

const
  consonants = "bdfghjklmnprstvz" ## 16 letters: 4 bits each
  vowels = "aiou" ## 4 letters: 2 bits each
  groupLen = 5

func quint16(x: uint16): string =
  $consonants[int(x shr 12) and 15] & $vowels[int(x shr 10) and 3] &
    $consonants[int(x shr 6) and 15] & $vowels[int(x shr 4) and 3] &
    $consonants[int(x) and 15]

func proquint*(bytes: openArray[byte]): string =
  ## The bytes (an even number of them) as groups of five letters: `[0x7f, 0, 0, 1]` -> "lusab-babad".
  for i in countup(0, bytes.high - 1, 2):
    if result.len > 0:
      result.add '-'
    result.add quint16(uint16(bytes[i]) shl 8 or uint16(bytes[i + 1]))

func fromProquint*(s: string): Option[seq[byte]] =
  ## The bytes of a proquint, none if it is not one.
  var bytes: seq[byte]
  var i = 0
  while i < s.len:
    if i + groupLen > s.len:
      return none(seq[byte])
    var x = 0'u16
    for j in 0 ..< groupLen:
      let c = s[i + j]
      let v =
        if j mod 2 == 0:
          consonants.find(c)
        else:
          vowels.find(c)
      if v < 0:
        return none(seq[byte])
      x = x shl (if j mod 2 == 0: 4 else: 2) or uint16(v)
    bytes.add byte(x shr 8)
    bytes.add byte(x and 0xff)
    i += groupLen
    if i < s.len:
      if s[i] != '-' or i + 1 >= s.len:
        return none(seq[byte])
      inc i
  if bytes.len == 0:
    none(seq[byte])
  else:
    some(bytes)

func isProquint*(s: string): bool =
  ## Whether the text is a proquint.
  fromProquint(s).isSome

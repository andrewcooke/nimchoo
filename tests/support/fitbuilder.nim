## Helpers for building small FIT files by hand in tests.

import nimchoo/fit/crc

const
  enumT* = 0x00
  sint32T* = 0x85
  uint8T* = 0x02
  uint16T* = 0x84
  uint32T* = 0x86
  stringT* = 0x07
  byteT* = 0x0d

func le16*(x: int): seq[byte] =
  @[byte(x and 0xff), byte((x shr 8) and 0xff)]
func be16*(x: int): seq[byte] =
  @[byte((x shr 8) and 0xff), byte(x and 0xff)]
func le32*(x: int64): seq[byte] =
  for i in 0 ..< 4:
    result.add byte((x shr (8 * i)) and 0xff)
func be32*(x: int64): seq[byte] =
  for i in countdown(3, 0):
    result.add byte((x shr (8 * i)) and 0xff)

func b*(xs: varargs[int]): seq[byte] =
  for x in xs:
    result.add byte(x)

func fitFile*(body: seq[byte]): seq[byte] =
  ## 12 byte header + body + CRC.
  var header =
    @[byte(12), 0x10] & le16(2000) & le32(body.len) &
    @[byte('.'), byte('F'), byte('I'), byte('T')]
  result = header & body
  result.add le16(int(crc16(result)))

func defn*(
    local, globalNum: int,
    fields: seq[(int, int, int)],
    big = false,
    dev: seq[(int, int, int)] = @[],
): seq[byte] =
  let hdr = 0x40 or local or (if dev.len > 0: 0x20 else: 0)
  result = @[byte(hdr), 0, byte(if big: 1 else: 0)]
  result.add(
    if big:
      be16(globalNum)
    else:
      le16(globalNum)
  )
  result.add byte(fields.len)
  for (n, s, t) in fields:
    result.add b(n, s, t)
  if dev.len > 0:
    result.add byte(dev.len)
    for (n, s, i) in dev:
      result.add b(n, s, i)

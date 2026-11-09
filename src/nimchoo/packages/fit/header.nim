## The FIT file header, and checks of it and of the file's checksums.

import std/[options, strutils]
import ../../core/errors
import ../util/warnings/warnings
import ../util/bytes/bytes
import ./crc

{.push raises: [].}

type FileHeader* = object
  size*: int ## byte 0 (12 or 14)
  protocolVersion*: int ## byte 1
  profileVersion*: int ## bytes 2-3
  dataSize*: int ## bytes 4-7
  dataType*: string ## bytes 8-11, should be ".FIT"
  checksum*: Option[uint16] ## bytes 12-13, if present and non-zero

proc readHeader*(data: openArray[byte]): FileHeader {.raises: [FitError].} =
  ## Raises FitError only if the data is too short to hold a header; use
  ## `problems` to check consistency.
  if data.len < 12:
    raiseFit("too short for a FIT header (" & $data.len & " bytes)")
  result.size = int(data[0])
  result.protocolVersion = int(data[1])
  result.profileVersion = int(getUint(data, 2, 2))
  result.dataSize = int(getUint(data, 4, 4))
  for i in 8 ..< 12:
    result.dataType.add char(data[i])
  if result.size >= 14 and data.len >= 14:
    let c = uint16(getUint(data, 12, 2))
    if c != 0:
      result.checksum = some(c)

func problems*(h: FileHeader, data: openArray[byte]): seq[Warning] =
  ## Inconsistencies in the header and the file checksums (empty if ok).
  ## The warnings have offset 0.
  if h.size < 12:
    result.add wkHeaderSizeSmall, 0, "Header size too small (" & $h.size & ")"
  elif h.size notin [12, 14]:
    result.add wkHeaderSizeOdd, 0, "Header size not standard (" & $h.size & "/12-14)"
  let expected = h.dataSize + h.size + 2
  if data.len != expected:
    result.add wkDataSize,
      0,
      "Data size incorrect (" & $data.len & "/" & $h.dataSize & "+" & $h.size & "+2=" &
        $expected & ")"
  if h.dataType != ".FIT":
    result.add wkDataType, 0, "Data type incorrect (" & escape(h.dataType) & ")"
  if h.checksum.isSome and data.len >= 12:
    let c = crc16(data.toOpenArray(0, 11))
    if c != h.checksum.get:
      result.add wkHeaderChecksum,
        0,
        "Inconsistent header checksum (" & toHex(c, 4) & "/" & toHex(h.checksum.get, 4) &
          ")"
  if data.len >= 2:
    let stored = uint16(getUint(data, data.len - 2, 2))
    let c = crc16(data.toOpenArray(0, data.len - 3))
    if c != stored:
      result.add wkFileChecksum,
        0, "Bad file checksum (" & toHex(c, 4) & "/" & toHex(stored, 4) & ")"

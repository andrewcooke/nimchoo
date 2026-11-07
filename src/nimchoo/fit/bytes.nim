## Reading numbers out of bytes: the one place for it.  Also reading a whole
## file as bytes.
##
## The `get` functions do not check bounds beyond the usual (reading outside
## `data` is a bug and raises an IndexDefect).  Where an offset or length comes
## from the file being read, call `canRead` first and raise your own error.

{.push raises: [].}

proc readBytes*(path: string): seq[byte] {.raises: [IOError].} =
  ## Whole file as bytes.
  let s = readFile(path)
  result = newSeq[byte](s.len)
  for i, c in s:
    result[i] = byte(c)

func canRead*(data: openArray[byte], offset, size: int): bool {.raises: [].} =
  ## Whether `size` bytes at `offset` are inside `data`.
  offset >= 0 and size >= 0 and offset <= data.len - size

func getUint*(
    data: openArray[byte], offset, size: int, endian: Endianness = littleEndian
): uint64 {.raises: [].} =
  ## The `size` (0 to 8) bytes at `offset` as an unsigned integer.
  for i in 0 ..< size:
    let b =
      if endian == littleEndian:
        data[offset + size - 1 - i]
      else:
        data[offset + i]
    result = (result shl 8) or uint64(b)

func getInt*(
    data: openArray[byte], offset, size: int, endian: Endianness = littleEndian
): int64 {.raises: [].} =
  ## The `size` (1 to 8) bytes at `offset` as a sign-extended integer.
  var u = getUint(data, offset, size, endian)
  if size < 8 and (u and (1'u64 shl (8 * size - 1))) != 0:
    u = u or (high(uint64) shl (8 * size))
  cast[int64](u)

func getBits*(
    data: openArray[byte], endian: Endianness, start, count: int
): uint64 {.raises: [].} =
  ## `count` (at most 64) bits of the integer that `data` represents, starting
  ## `start` bits up from the least significant end.  Bits beyond the data
  ## are zero.
  for k in 0 ..< count:
    let bit = start + k
    let bi = bit div 8
    if bi >= data.len:
      break
    let at =
      if endian == littleEndian:
        bi
      else:
        data.len - 1 - bi
    if ((data[at] shr (bit mod 8)) and 1) != 0:
      result = result or (1'u64 shl k)

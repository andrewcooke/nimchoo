## The FIT CRC.

const crcTable: array[16, uint16] = [
  0x0000'u16, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
  0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400]

func crc16*(data: openArray[byte], start: uint16 = 0): uint16 {.raises: [].} =
  ## FIT CRC.  Pass the previous result as `start` to continue incrementally.
  result = start
  for b in data:
    var tmp = crcTable[result and 0xf]
    result = (result shr 4) and 0xfff
    result = result xor tmp xor crcTable[b and 0xf]
    tmp = crcTable[result and 0xf]
    result = (result shr 4) and 0xfff
    result = result xor tmp xor crcTable[(b shr 4) and 0xf]

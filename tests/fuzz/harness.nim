## What every libFuzzer harness (tests/fuzz/TARGET.nim) shares.  A harness is built by `nimble fuzz TARGET` with clang, as
## a program whose `main` is libFuzzer's (`--noMain`); libFuzzer calls `LLVMFuzzerTestOneInput` with each input it makes.
## A Defect aborts the program (`--panics:on`), which libFuzzer records as a crash; the errors a reader is allowed to
## raise are caught by the target.  Not part of nimble test: the level-1 tests (tests/*/test_fuzz.nim) are.

proc NimMain() {.importc.}

proc LLVMFuzzerInitialize(argc: ptr cint, argv: ptr pointer): cint {.exportc.} =
  ## Starts Nim's runtime (the program has no Nim `main`) before the first input.
  NimMain()
  0

func asString*(data: ptr UncheckedArray[byte], len: csize_t): string =
  ## The input as the string that most of the readers take.
  result = newString(int(len))
  for i in 0 ..< int(len):
    result[i] = char(data[i])

func asBytes*(data: ptr UncheckedArray[byte], len: csize_t): seq[byte] =
  ## The input as the bytes that the FIT readers take.
  result = newSeq[byte](int(len))
  for i in 0 ..< int(len):
    result[i] = data[i]

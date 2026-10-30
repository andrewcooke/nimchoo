## Reading a whole FIT file: tokenizer and decoder together, as a stream of
## events or records.  Records must be decoded in file order (developer fields
## are described by earlier records), which the iterators guarantee.

import std/[algorithm, options]
import ../errors
import ../profile/model
import ../warnings
import ./decode
import ./records
import ./tokens

{.push raises: [].}

type
  Reader* = object
    tokenizer*: Tokenizer
    decoder*: Decoder
    started: bool

proc initReader*(p: Profile, data: sink seq[byte]): Reader =
  Reader(tokenizer: initTokenizer(data, p.timestamp16Fields),
         decoder: initDecoder(p))

func warnings*(r: Reader): seq[Warning] =
  ## The tokenizer's and the decoder's warnings, in file order.
  result = r.tokenizer.warnings & r.decoder.warnings
  result.sort do (a, b: Warning) -> int: cmp(a.offset, b.offset)

iterator events*(r: var Reader, p: Profile): Event {.raises: [FitError].} =
  ## Every definition and data message in the file, in order.  Raises
  ## FitError as the tokenizer does (events before the error have already been
  ## yielded).
  while true:
    let tok = r.tokenizer.next()
    if tok.isNone: break
    case tok.get.kind
    of tokHeader:
      if r.started:  # chained file: accumulators and developer fields restart
        r.decoder.resetFile()
      r.started = true
    of tokDefinition:
      yield r.decoder.definitionEvent(p, r.tokenizer, tok.get)
    of tokData:
      yield Event(kind: evRecord, offset: tok.get.offset,
                  record: r.decoder.decode(p, r.tokenizer, tok.get))
    else: discard

iterator records*(r: var Reader, p: Profile): Record {.raises: [FitError].} =
  ## Every data message in the file, in order (see `events`).
  for ev in r.events(p):
    if ev.kind == evRecord: yield ev.record

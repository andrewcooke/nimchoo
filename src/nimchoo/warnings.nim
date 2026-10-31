## Warnings: oddities in a file that do not stop us reading it.  They are
## collected (never logged or printed by library code), each with a kind so
## that callers and tests can act on what happened rather than on its text.
## Things that do stop us are errors (see errors.nim).

{.push raises: [].}

type
  WarningKind* = enum
    # the file header and checksums
    wkHeaderSizeSmall    ## header size below the minimum of 12
    wkHeaderSizeOdd      ## header size not 12 or 14
    wkDataSize           ## file length does not match the header's data size
    wkDataType           ## the header does not say ".FIT"
    wkHeaderChecksum     ## header checksum does not match
    wkFileChecksum       ## file checksum does not match
    # tokenizing
    wkDataSizeIgnored    ## header data size unusable; read to the end of the file
    wkTrailingBytes      ## bytes after the last file that are not another file
    wkReservedBit        ## reserved bit set in a record header
    wkUnknownBaseType    ## a definition names a base type we do not know
    wkTimestampSize      ## timestamp field is not 4 bytes
    wkTimestamp16Size    ## timestamp_16 field is not 2 bytes
    wkTimestamp16NoBase  ## timestamp_16 before any full timestamp
    wkTimestamp16Backwards  ## timestamp_16 moved back in time
    # decoding
    wkCannotAccumulate   ## an accumulated field has several values
    wkNestingTooDeep     ## components nested too deeply
    wkCompositeSize      ## a composite field cannot be expanded (size)
    wkCompositeTarget    ## a composite component names a missing field
    wkFieldDescription   ## a field_description record is unusable
    wkUndescribedDevField  ## developer field with no field_description
    # importing activities
    wkDuplicateTime      ## several records in one second (the last is kept)
    wkInvalidTime        ## a timestamp that is not a calendar time (dropped)

  Warning* = object
    offset*: int        ## byte offset in the file
    kind*: WarningKind
    msg*: string        ## the details, for people

proc add*(ws: var seq[Warning], kind: WarningKind, offset: int,
          msg: string) {.raises: [].} =
  ws.add Warning(offset: offset, kind: kind, msg: msg)

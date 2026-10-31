## The error types of nimchoo.  Input that cannot be used (a corrupt file, a
## bad profile) raises a subtype of `NchError`, carrying where the problem is
## as fields as well as in the message.  (Bugs are not errors: they are
## Defects, from `doAssert`/`raiseAssert` and the built-in checks.  Ordinary
## absence is an `Option`.  See "Conventions" in TODO.md.)

{.push raises: [].}

type
  NchError* = object of CatchableError
    ## Base of all errors raised on unusable input.

  FitError* = object of NchError
    ## A FIT file that cannot be read (further).
    offset*: int  ## byte offset in the file, or -1 if not known

  ProfileError* = object of NchError
    ## A profile spreadsheet that cannot be used.
    sheet*: string  ## "" if not about a particular sheet
    row*: int       ## 1-based spreadsheet row, 0 if not known

  XlsxError* = object of NchError
    ## A file that is not a readable xlsx file.

  StoreError* = object of NchError
    ## The database cannot be used (cannot be opened or created, a query
    ## failed, a constraint was violated).

  ImportError* = object of NchError
    ## A file that is readable but cannot be imported as an activity.

proc raiseFit*(msg: string) {.noreturn, raises: [FitError].} =
  ## Raise a FitError that has no offset.
  raise (ref FitError)(msg: msg, offset: -1)

proc raiseFit*(offset: int, msg: string) {.noreturn, raises: [FitError].} =
  ## Raise a FitError at a byte offset; the offset is added to the message.
  raise (ref FitError)(msg: msg & " (at offset " & $offset & ")", offset: offset)

proc raiseProfile*(msg: string, sheet = "", row = 0) {.noreturn,
    raises: [ProfileError].} =
  ## Raise a ProfileError, optionally for a 1-based `row` of `sheet`.
  raise (ref ProfileError)(msg: msg, sheet: sheet, row: row)

proc raiseXlsx*(msg: string) {.noreturn, raises: [XlsxError].} =
  raise (ref XlsxError)(msg: msg)

proc raiseStore*(msg: string) {.noreturn, raises: [StoreError].} =
  raise (ref StoreError)(msg: msg)

proc raiseImport*(msg: string) {.noreturn, raises: [ImportError].} =
  raise (ref ImportError)(msg: msg)

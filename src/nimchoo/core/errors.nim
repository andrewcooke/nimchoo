## The error types of nimchoo.  Input that cannot be used (a corrupt file, a
## bad profile) raises a subtype of `NchError`, carrying where the problem is
## as fields as well as in the message.  (Bugs are not errors: they are
## Defects, from `doAssert`/`raiseAssert` and the built-in checks.  Ordinary
## absence is an `Option`.  See "Conventions" in CLAUDE.md.)

import std/options

{.push raises: [].}

type
  NchError* = object of CatchableError ## Base of all errors raised on unusable input.

  FitError* = object of NchError ## A FIT file that cannot be read (further).
    offset*: Option[int] ## byte offset in the file, if known

  ProfileError* = object of NchError ## A profile spreadsheet that cannot be used.
    sheet*: Option[string] ## the sheet, if it is about a particular one
    row*: Option[int] ## 1-based spreadsheet row, if known

  XlsxError* = object of NchError ## A file that is not a readable xlsx file.

  ZipError* = object of NchError
    ## Bytes that are not a readable zip file, or an entry that cannot be read.

  StoreError* = object of NchError
    ## The database cannot be used (cannot be opened or created, a query
    ## failed, a constraint was violated).

  DownloadError* = object of NchError
    ## A file that was needed from the network could not be had (no connection, the server said no, the file is
    ## not what it should be).  The message says what and why.

  OfflineError* = object of DownloadError
    ## The same, because `--offline` was given and the file is not in the cache: not a failure but a choice, so what needs
    ## it is left undone (the names stay null) and the next run that may use the network does it.

  TemplateError* = object of NchError
    ## A page template that cannot be used (a tag not closed, a name the values do not have).
    line*: Option[int] ## 1-based line of the template, if known

  ImportFailure* = enum
    ifNoActivity ## the file has no activity in it (no session message)
    ifBadTime ## its times are not calendar times
    ifMonitor
      ## a file that says it is not an activity (monitoring and other all-day data): none is expected

  PackageError* = object of NchError
    ## The packages do not fit together (a cycle, a missing dependency, a name used twice).  Raised while the
    ## program is compiled, so it stops the build with this message.

  ImportError* = object of NchError
    ## A file that is readable but cannot be imported as an activity.
    kind*: ImportFailure

proc raiseFit*(msg: string) {.noreturn, raises: [FitError].} =
  ## Raise a FitError that has no offset.
  raise (ref FitError)(msg: msg, offset: none(int))

proc raiseFit*(offset: int, msg: string) {.noreturn, raises: [FitError].} =
  ## Raise a FitError at a byte offset; the offset is added to the message.
  raise (ref FitError)(msg: msg & " (at offset " & $offset & ")", offset: some(offset))

proc raiseProfile*(msg: string) {.noreturn, raises: [ProfileError].} =
  ## Raise a ProfileError that is not about a particular place.
  raise (ref ProfileError)(msg: msg)

proc raiseProfile*(
    msg: string, sheet: string, row: int
) {.noreturn, raises: [ProfileError].} =
  ## Raise a ProfileError for a 1-based `row` of `sheet`.
  raise (ref ProfileError)(msg: msg, sheet: some(sheet), row: some(row))

proc raiseXlsx*(msg: string) {.noreturn, raises: [XlsxError].} =
  ## Raise an XlsxError.
  raise (ref XlsxError)(msg: msg)

proc raiseZip*(msg: string) {.noreturn, raises: [ZipError].} =
  ## Raise a ZipError.
  raise (ref ZipError)(msg: msg)

proc raiseStore*(msg: string) {.noreturn, raises: [StoreError].} =
  ## Raise a StoreError.
  raise (ref StoreError)(msg: msg)

proc raisePackage*(msg: string) {.noreturn, raises: [PackageError].} =
  ## Raise a PackageError.
  raise (ref PackageError)(msg: msg)

proc raiseImport*(
    kind: ImportFailure, msg: string
) {.noreturn, raises: [ImportError].} =
  ## Raise an ImportError of the given kind.
  raise (ref ImportError)(msg: msg, kind: kind)

proc raiseTemplate*(msg: string) {.noreturn, raises: [TemplateError].} =
  ## Raise a TemplateError that is not about a particular line.
  raise (ref TemplateError)(msg: msg)

proc raiseTemplate*(msg: string, line: int) {.noreturn, raises: [TemplateError].} =
  ## Raise a TemplateError for a 1-based `line` of the template.
  raise (ref TemplateError)(msg: "line " & $line & ": " & msg, line: some(line))

type
  ThemeError* = object of NchError
    ## A theme file that cannot be used (a bad colour, an unknown attribute).
    line*: Option[int] ## 1-based line of the file, if known

  MarkupError* = object of NchError
    ## Styled text that cannot be read (a bracket not closed, an unknown style).
    column*: Option[int]
      ## 1-based position in the text (in bytes, counting every line), if known

proc raiseTheme*(msg: string) {.noreturn, raises: [ThemeError].} =
  ## Raise a ThemeError that is not about a particular line.
  raise (ref ThemeError)(msg: msg)

proc raiseTheme*(msg: string, line: int) {.noreturn, raises: [ThemeError].} =
  ## Raise a ThemeError for a 1-based `line` of the file.
  raise (ref ThemeError)(msg: "line " & $line & ": " & msg, line: some(line))

proc raiseMarkup*(msg: string, column: int) {.noreturn, raises: [MarkupError].} =
  ## Raise a MarkupError at a 1-based `column` of the text.
  raise (ref MarkupError)(msg: "at " & $column & ": " & msg, column: some(column))

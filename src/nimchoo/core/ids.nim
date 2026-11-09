## Row ids of the tables that other tables point at.  Each is its own type, so an activity id cannot
## be given where a file or a user is wanted (they are all numbers to SQLite, and a mix-up there is
## a wrong row, not an error).

import std/hashes

{.push raises: [].}

type
  UserId* = distinct int64
  ActivityId* = distinct int64
  FileId* = distinct int64
  ModelId* = distinct int64

  AnyId* = UserId | ActivityId | FileId | ModelId

func `==`*(a, b: UserId): bool {.borrow.}
func `==`*(a, b: ActivityId): bool {.borrow.}
func `==`*(a, b: FileId): bool {.borrow.}
func `==`*(a, b: ModelId): bool {.borrow.}
func `<`*(a, b: UserId): bool {.borrow.}
func `<`*(a, b: ActivityId): bool {.borrow.}
func `<`*(a, b: FileId): bool {.borrow.}
func `<`*(a, b: ModelId): bool {.borrow.}
func `$`*(a: UserId): string {.borrow.}
func `$`*(a: ActivityId): string {.borrow.}
func `$`*(a: FileId): string {.borrow.}
func `$`*(a: ModelId): string {.borrow.}
func hash*(a: UserId): Hash {.borrow.}
func hash*(a: ActivityId): Hash {.borrow.}
func hash*(a: FileId): Hash {.borrow.}
func hash*(a: ModelId): Hash {.borrow.}

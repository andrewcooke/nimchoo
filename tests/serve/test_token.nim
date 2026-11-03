import std/[os, strutils, unittest]
import nimchoo/serve/token

let dir = getTempDir() / "nch-test-token"

suite "serve token":
  test "made on first use: 32 hex digits, in a file only the user can read":
    removeDir(dir)
    let (t, problem) = loadToken(dir / "cache")
    check problem == ""
    check isToken(t)
    let path = dir / "cache" / tokenFileName
    check fileExists(path)
    check getFilePermissions(path) == {fpUserRead, fpUserWrite}
    check readFile(path).strip == t
  test "kept: the same next time":
    removeDir(dir)
    let a = loadToken(dir).token
    check loadToken(dir).token == a
  test "renewed on request, and then kept":
    removeDir(dir)
    let a = loadToken(dir).token
    let b = loadToken(dir, renew = true).token
    check isToken(b) and b != a
    check loadToken(dir).token == b
  test "a file that is not a token is replaced":
    removeDir(dir)
    createDir(dir)
    writeFile(dir / tokenFileName, "not a token\n")
    check isToken(loadToken(dir).token)
    writeFile(dir / tokenFileName, "ABCDEF0123456789ABCDEF0123456789\n")    # (upper case: not ours)
    check isToken(loadToken(dir).token)
  test "two tokens are not the same":
    removeDir(dir)
    let a = loadToken(dir, renew = true).token
    let b = loadToken(dir, renew = true).token
    check a != b
  test "a place that cannot be written is a problem, not a crash":
    removeDir(dir)
    createDir(dir)
    writeFile(dir / "file", "")
    let r = loadToken(dir / "file" / "cache")
    check r.token == "" and r.problem.contains("cannot keep the server's token")
  test "what is a token":
    check isToken("0123456789abcdef0123456789abcdef")
    for bad in ["", "abc", "0123456789ABCDEF0123456789abcdef", "0123456789abcdef0123456789abcdeg",
                "0123456789abcdef0123456789abcdef0"]:
      check not isToken(bad)

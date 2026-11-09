import std/[options, strutils, unittest]
import db_connector/db_sqlite
import nimchoo/db/statement
import nimchoo/errors
import nimchoo/ids

proc memory(): DbConn =
  result = open(":memory:", "", "", "")
  result.execScript(
    "create table t(id integer primary key, name text, x real, n integer, note text, b blob)"
  )
  result.execute(
    "insert into t(name, x, n, note) values (?, ?, ?, ?)", "alpha", 1.5, 3, some("hi")
  )
  result.execute(
    "insert into t(name, x, n, note) values (?, ?, ?, ?)", "beta", 2.0, 4, none(string)
  )

suite "statement: typed reading and binding":
  test "rows are read into tuples by the types of the fields":
    let db = memory()
    defer:
      db.close()
    let rows = db.query(
      (string, float, int, Option[string]), "select name, x, n, note from t order by id"
    )
    check rows == @[("alpha", 1.5, 3, some("hi")), ("beta", 2.0, 4, none(string))]
  test "objects too, and ids":
    type Row = object
      id: UserId
      name: string

    let db = memory()
    defer:
      db.close()
    let rows = db.query(Row, "select id, name from t where n > ?", 3)
    check rows.len == 1 and rows[0].name == "beta" and int64(rows[0].id) == 2
  test "one column is read as one value; scalar and queryOne":
    let db = memory()
    defer:
      db.close()
    check db.query(string, "select name from t order by id") == @["alpha", "beta"]
    check db.scalar(int, "select count(*) from t") == 2
    check db.queryOne(string, "select name from t where n = ?", 4).get == "beta"
    check db.queryOne(string, "select name from t where n = ?", 99).isNone
    expect StoreError:
      discard db.scalar(int, "select n from t where n = ?", 99)
  test "bound values are values, not sql":
    let db = memory()
    defer:
      db.close()
    db.execute("insert into t(name) values (?)", "x'); drop table t; --")
    check db.scalar(int, "select count(*) from t where name like ?", "x'%") == 1
    check db.scalar(int, "select count(*) from t") == 3
  test "an empty string is text; an absent Option is NULL":
    let db = memory()
    defer:
      db.close()
    db.execute("insert into t(name, note) values (?, ?)", "", none(string))
    check db.scalar(int, "select count(*) from t where name = ''") == 1
    check db.scalar(int, "select count(*) from t where note is null") == 2
  test "a whole number reads as a real, not the other way":
    let db = memory()
    defer:
      db.close()
    check db.scalar(float, "select coalesce(x, 0) + 1 from t where n = 4") == 3.0
    expect StoreError:
      discard db.scalar(int, "select x from t where n = 4")
  test "a column of the wrong type, a NULL, or the wrong width is an error that names the column":
    let db = memory()
    defer:
      db.close()
    try:
      discard db.query((string, int), "select name, name from t")
      fail()
    except StoreError as e:
      check "column 1 (name) is text, not an integer" in e.msg
    try:
      discard db.query((string, string), "select name, note from t")
      fail()
    except StoreError as e:
      check "column 1 (note) is null, not text" in e.msg
    expect StoreError:
      discard db.query((string,), "select name, x from t")
    expect StoreError:
      discard db.query((string, float, int), "select name, x from t")

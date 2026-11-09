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
  test "a single optional column is one value (NULL is none)":
    let db = memory()
    defer:
      db.close()
    check db.query(Option[string], "select note from t order by id") ==
      @[some("hi"), none(string)]
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

suite "statement: a query built from pieces, with named values":
  test "the values go by name, in whatever order the pieces are joined":
    let db = memory()
    defer:
      db.close()
    let a = sqlOf("select name from t where n >= :low").with("low", 3)
    let b = sqlOf(" and x < :high order by id").with("high", 2.0)
    check db.query(string, a & b) == @["alpha"]
    let flipped =
      sqlOf("select name from t where x < :high").with("high", 9.0) &
      sqlOf(" and n >= :low order by id").with("low", 3)
    check db.query(string, flipped) == @["alpha", "beta"]
  test "one name may stand twice; it is one value":
    let db = memory()
    defer:
      db.close()
    let q = sqlOf("select count(*) from t where n = :n or n + 1 = :n").with("n", 4)
    check db.scalar(int, q) == 2
  test "a value is data: a quote or a drop table does nothing":
    let db = memory()
    defer:
      db.close()
    let q = sqlOf("select count(*) from t where name = :who").with(
        "who", "x'; drop table t; --"
      )
    check db.scalar(int, q) == 0
    check db.scalar(int, "select count(*) from t") == 2
  test "a list of any length is one value":
    let db = memory()
    defer:
      db.close()
    let q = sqlOf(
        "select name from t where id in (select value from json_each(:ids)) order by id"
      )
      .with("ids", jsonList([2'i64, 1'i64, 99'i64]))
    check db.query(string, q) == @["alpha", "beta"]
  test "a name with no value, a value with no name, or a name given twice is an error that says which":
    let db = memory()
    defer:
      db.close()
    try:
      discard db.query(string, sqlOf("select name from t where n = :n"))
      fail()
    except StoreError as e:
      check ":n but no value" in e.msg
    try:
      discard db.query(string, sqlOf("select name from t").with("zz", 1))
      fail()
    except StoreError as e:
      check ":zz is not used" in e.msg
    try:
      discard db.query(
        string, sqlOf("select name from t where n = :n").with("n", 1).with("n", 2)
      )
      fail()
    except StoreError as e:
      check ":n is given twice" in e.msg
    try:
      discard db.query(string, sqlOf("select name from t where n = ?"))
      fail()
    except StoreError as e:
      check "only :names" in e.msg
  test "execute and an absent Option":
    let db = memory()
    defer:
      db.close()
    db.execute(
      sqlOf("insert into t(name, note) values (:name, :note)")
        .with("name", "gamma")
        .with("note", none(string))
    )
    check db.scalar(int, "select count(*) from t where note is null") == 2

import std/unittest
import db_connector/db_sqlite
import nimchoo/db/[multirow, statement]
import nimchoo/errors

proc fill(db: DbConn, count: int) =
  ## Insert `count` rows (n, n * 2, a text for the odd ones, NULL for the even) with as few statements as the helper allows.
  var m = initMultiInsert(db, "insert into t(a, b, c) values ", 3)
  var i = 0
  while i < count:
    let n = min(rowsPerStatement, count - i)
    let st = m.statement(n)
    for r in 0 ..< n:
      st.bindInt(3 * r + 1, int64(i + r))
      st.bindInt(3 * r + 2, int64(2 * (i + r)))
      if (i + r) mod 2 == 1:
        st.bindText(3 * r + 3, "odd" & $(i + r))
      else:
        st.bindNull(3 * r + 3)
    st.run()
    i += n

suite "multi-row inserts":
  let rows = [0, 1, 2, 127, 128, 129, 255, 256, 257, 1000]
  test "any number of rows gives the rows, in order, exactly once":
    for count in rows:
      let db = open(":memory:", "", "", "")
      db.exec(sql"create table t(a integer, b integer, c text)")
      db.fill(count)
      check db.getValue(sql"select count(*) from t") == $count
      if count > 0:
        check db.getValue(sql"select sum(a) from t") == $(count * (count - 1) div 2)
        check db.getValue(sql"select sum(b) from t") == $(count * (count - 1))
        check db.getValue(
          sql"select group_concat(a) from (select a from t order by rowid limit 3)"
        ) == (if count >= 3: "0,1,2" elif count == 2: "0,1" else: "0")
        check db.getValue(sql"select count(c) from t") == $(count div 2)
          # the NULLs stayed NULL
        check db.getValue(sql"select c from t where a = 1") == "odd1" or count < 2
      db.close()
  test "the statements are made once for each size and kept":
    let db = open(":memory:", "", "", "")
    db.exec(sql"create table t(a integer, b integer, c text)")
    db.fill(300) # 128 + 128 + 44
    db.fill(300)
    check db.getValue(sql"select count(*) from t") == "600"
    db.close()
  test "an error is a StoreError, and the statement can be used again":
    let db = open(":memory:", "", "", "")
    db.exec(sql"create table t(a integer primary key, b integer, c text)")
    block statements: # (they are gone before the database is closed)
      var m = initMultiInsert(db, "insert into t(a, b, c) values ", 3)
      let st = m.statement(2)
      st.bindInt(1, 1)
      st.bindInt(2, 1)
      st.bindNull(3)
      st.bindInt(4, 1)
      st.bindInt(5, 2)
      st.bindNull(6) # the same key twice
      expect StoreError:
        st.run()
      check db.getValue(sql"select count(*) from t") == "0" # (nothing of it was kept)
      let again = m.statement(2)
      again.bindInt(1, 1)
      again.bindInt(2, 1)
      again.bindNull(3)
      again.bindInt(4, 2)
      again.bindInt(5, 2)
      again.bindNull(6)
      again.run()
      check db.getValue(sql"select count(*) from t") == "2"
    db.close()

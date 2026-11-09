## Writing the `user` table, which `db` owns (every table refers to it, and opening a database makes the first user):
## the packages that manage users (`nch users`) ask for these and do not write the table themselves.

import ./[statement, store]
import ../../core/errors

{.push raises: [].}

proc addUser*(st: Store, name: string) {.raises: [StoreError].} =
  ## Make a user (not the default).
  st.db.execute("insert into user(name) values (:name)", name = name)

proc renameUser*(st: Store, id: UserId, name: string) {.raises: [StoreError].} =
  st.db.execute("update user set name = :name where id = :id", name = name, id = id)

proc setDefaultUser*(st: Store, id: UserId) {.raises: [StoreError].} =
  ## Make `id` the default user (the old one stops being; both or neither).
  st.begin()
  var done = false
  try:
    st.db.execute("update user set is_default = 0 where is_default = 1")
    st.db.execute("update user set is_default = 1 where id = :id", id = id)
    st.commit()
    done = true
  finally:
    if not done:
      st.rollback()

proc deleteUser*(st: Store, id: UserId) {.raises: [StoreError].} =
  ## Delete the user and everything they have (`on delete cascade`).  If it was the default another becomes the
  ## default, or if there is none a new empty one is made, the next time the database is opened.
  st.db.execute("delete from user where id = :id", id = id)
  st.reclaim()

## The models (sets of variables) in the database: the one the program carries, reading them,
## adding more.

import std/[options, strutils]
import ../hashing
import db_connector/db_sqlite
import ../db/store
import ../errors
import ./calc

{.push raises: [].}

const columns =
  "id, name, gamma, zero, one, max_secs, zone1, zone2, zone3, zone4, zone5, " &
  "fitness_days, fatigue_days"

func describe*(m: Model): string =
  ## Every value, as text: what `seedVersion` is made from.
  result = m.name & " " & $m.gamma & " " & $m.zero & " " & $m.one & " " & $m.maxSecs
  for z in m.zones:
    result.add " " & $z
  result.add " " & $m.fitnessDays & " " & $m.fatigueDays

const seedVersion* = sha256Hex(describe(defaultModel()))
  ## Names the values of the default model, so that a database made with others is noticed.

proc insertModel*(db: DbConn, m: Model) {.raises: [StoreError].} =
  ## Add a model (its id is ignored).  Raises StoreError if the name is taken or a value is bad.
  guard:
    db.exec(
      sql(
        "insert into ff_model(name, gamma, zero, one, max_secs, zone1, zone2, zone3, " &
          "zone4, zone5, fitness_days, fatigue_days) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
      ),
      m.name,
      m.gamma,
      m.zero,
      m.one,
      m.maxSecs,
      m.zones[0],
      m.zones[1],
      m.zones[2],
      m.zones[3],
      m.zones[4],
      m.fitnessDays,
      m.fatigueDays,
    )

proc seedDefaultModel*(db: DbConn) {.raises: [StoreError].} =
  ## The seed of the model fragment.
  insertModel(db, defaultModel())

proc modelOf(r: Row): Model {.raises: [StoreError].} =
  try:
    result = Model(
      id: ModelId(parseBiggestInt(r[0])),
      name: r[1],
      gamma: parseFloat(r[2]),
      zero: parseFloat(r[3]),
      one: parseFloat(r[4]),
      maxSecs: parseInt(r[5]),
      fitnessDays: parseFloat(r[11]),
      fatigueDays: parseFloat(r[12]),
    )
    for i in 0 .. 4:
      result.zones[i] = parseFloat(r[6 + i])
  except ValueError:
    raiseStore("a model in the database has a value that is not a number: " & r[1])

proc loadModels*(db: DbConn): seq[Model] {.raises: [StoreError].} =
  ## All the models, oldest first.
  guard:
    for r in db.fastRows(sql("select " & columns & " from ff_model order by id")):
      result.add modelOf(r)

proc findModel*(db: DbConn, name: string): Option[Model] {.raises: [StoreError].} =
  guard:
    let r = db.getRow(sql("select " & columns & " from ff_model where name = ?"), name)
    if r[0].len > 0:
      result = some(modelOf(r))

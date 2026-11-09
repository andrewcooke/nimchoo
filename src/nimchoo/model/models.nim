## The models (sets of variables) in the database: the one the program carries, reading them,
## adding more.

import std/options
import ../hashing
import db_connector/db_sqlite
import ../db/[statement, store]
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
  db.execute(
    "insert into ff_model(name, gamma, zero, one, max_secs, zone1, zone2, zone3, " &
      "zone4, zone5, fitness_days, fatigue_days) values (:name, :gamma, :zero, :one, :maxSecs, :zone1, :zone2, :zone3, :zone4, :zone5, :fitnessDays, :fatigueDays)",
    name = m.name,
    gamma = m.gamma,
    zero = m.zero,
    one = m.one,
    maxSecs = m.maxSecs,
    zone1 = m.zones[0],
    zone2 = m.zones[1],
    zone3 = m.zones[2],
    zone4 = m.zones[3],
    zone5 = m.zones[4],
    fitnessDays = m.fitnessDays,
    fatigueDays = m.fatigueDays,
  )

proc seedDefaultModel*(db: DbConn) {.raises: [StoreError].} =
  ## The seed of the model fragment.
  insertModel(db, defaultModel())

type ModelRow =
  tuple[
    id: ModelId,
    name: string,
    gamma, zero, one: float,
    maxSecs: int,
    zone1, zone2, zone3, zone4, zone5, fitnessDays, fatigueDays: float,
  ]

func modelOf(r: ModelRow): Model =
  Model(
    id: r.id,
    name: r.name,
    gamma: r.gamma,
    zero: r.zero,
    one: r.one,
    maxSecs: r.maxSecs,
    zones: [r.zone1, r.zone2, r.zone3, r.zone4, r.zone5],
    fitnessDays: r.fitnessDays,
    fatigueDays: r.fatigueDays,
  )

proc loadModels*(db: DbConn): seq[Model] {.raises: [StoreError].} =
  ## All the models, oldest first.
  for r in db.query(ModelRow, "select " & columns & " from ff_model order by id"):
    result.add modelOf(r)

proc findModel*(db: DbConn, name: string): Option[Model] {.raises: [StoreError].} =
  ## The model called `name`, if there is one.
  let r = db.queryOne(
    ModelRow, "select " & columns & " from ff_model where name = :name", name = name
  )
  if r.isSome:
    result = some(modelOf(r.get))

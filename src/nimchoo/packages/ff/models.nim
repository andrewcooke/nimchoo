## The models (sets of variables) in the database: the one the program carries, reading them, adding, changing and
## deleting the others, finding them by patterns of names, and the models selection of a user.

import std/[json, options, sequtils, strformat]
import ../util/hashing/hashing
import ../db/[sqltext, statement, store]
import ../../core/[errors, ids]
import ../subject/subjects
import ../tags/tag
import ../text/fold/fold
import ./calc

{.push raises: [].}

const columns =
  "m.id, m.name, m.built_in, m.gamma, m.zero, m.one, m.max_secs, m.zone1, m.zone2, m.zone3, m.zone4, m.zone5, m.ceiling, " &
  "m.fitness_days, m.fatigue_days, m.fitness_scale, m.fatigue_scale"

func describe*(m: Model): string =
  ## Every value, as text: what `seedVersion` is made from.
  result = fmt"{m.name} {m.gamma} {m.zero} {m.one} {m.maxSecs}"
  for z in m.zones:
    result.add fmt" {z}"
  result.add fmt" {m.ceiling}"
  result.add fmt" {m.fitnessDays} {m.fatigueDays} {m.fitnessScale} {m.fatigueScale}"
  for p in m.patterns:
    result.add fmt" {p}"

const seedVersion* = sha256Hex(describe(defaultModel()))
  ## Names the values of the default model, so that a database made with others is noticed.

func foldedName*(name: string): string =
  ## A model's name as it is matched (and kept unique): lower case, no accents, as a tag is.
  foldText(name)

proc writePatterns(
    db: DbConn, id: ModelId, patterns: seq[TagPattern]
) {.raises: [StoreError].} =
  db.execute("delete from ff_model_pattern where model_id = :id", id = id)
  for p in patterns:
    db.execute(
      "insert or ignore into ff_model_pattern(model_id, pattern, folded) values (:id, :pattern, :folded)",
      id = id,
      pattern = $p,
      folded = foldedPattern(p),
    )

proc insertModel*(db: DbConn, m: Model): ModelId {.raises: [StoreError].} =
  ## Add a model (its id is ignored); its new id.  Raises StoreError if the name is taken or a value is bad.
  db.execute(
    """insert into ff_model(name, folded, built_in, gamma, zero, one, max_secs, zone1, zone2, zone3, zone4, zone5,
        ceiling, fitness_days, fatigue_days, fitness_scale, fatigue_scale)
      values (:name, :folded, :builtIn, :gamma, :zero, :one, :maxSecs, :zone1, :zone2, :zone3, :zone4, :zone5, :ceiling,
        :fitnessDays, :fatigueDays, :fitnessScale, :fatigueScale)""",
    name = m.name,
    folded = foldedName(m.name),
    builtIn = (if m.builtIn: 1 else: 0),
    gamma = m.gamma,
    zero = m.zero,
    one = m.one,
    maxSecs = m.maxSecs,
    zone1 = m.zones[0],
    zone2 = m.zones[1],
    zone3 = m.zones[2],
    zone4 = m.zones[3],
    zone5 = m.zones[4],
    ceiling = m.ceiling,
    fitnessDays = m.fitnessDays,
    fatigueDays = m.fatigueDays,
    fitnessScale = m.fitnessScale,
    fatigueScale = m.fatigueScale,
  )
  result = ModelId(db.scalar(int64, "select last_insert_rowid()"))
  writePatterns(db, result, m.patterns)

proc updateModel*(db: DbConn, old, m: Model) {.raises: [StoreError].} =
  ## Change the model `old` (by its id) to `m`.  If the impulses it gives change, those worked out with it are deleted, to
  ## be worked out again when they are wanted.
  doAssert old.id == m.id
  db.execute(
    """update ff_model set name = :name, folded = :folded, gamma = :gamma, zero = :zero, one = :one,
        max_secs = :maxSecs, zone1 = :zone1, zone2 = :zone2, zone3 = :zone3, zone4 = :zone4, zone5 = :zone5, ceiling = :ceiling,
        fitness_days = :fitnessDays, fatigue_days = :fatigueDays, fitness_scale = :fitnessScale,
        fatigue_scale = :fatigueScale
      where id = :id""",
    id = m.id,
    name = m.name,
    folded = foldedName(m.name),
    gamma = m.gamma,
    zero = m.zero,
    one = m.one,
    maxSecs = m.maxSecs,
    zone1 = m.zones[0],
    zone2 = m.zones[1],
    zone3 = m.zones[2],
    zone4 = m.zones[3],
    zone5 = m.zones[4],
    ceiling = m.ceiling,
    fitnessDays = m.fitnessDays,
    fatigueDays = m.fatigueDays,
    fitnessScale = m.fitnessScale,
    fatigueScale = m.fatigueScale,
  )
  writePatterns(db, m.id, m.patterns)
  if not sameImpulse(old, m):
    db.execute("delete from impulse where model_id = :id", id = m.id)

proc deleteModels*(db: DbConn, ids: seq[ModelId]) {.raises: [StoreError].} =
  ## Delete the models (with their impulses, patterns and places in selections).
  for id in ids:
    db.execute("delete from ff_model where id = :id", id = id)

proc seedDefaultModel*(db: DbConn) {.raises: [StoreError].} =
  ## The seed of the model fragment: the built-in model, selected for the users there are.
  let id = insertModel(db, defaultModel())
  db.execute(
    "insert into model_selection(user_id, model_id) select id, :id from user", id = id
  )

type ModelRow =
  tuple[
    id: ModelId,
    name: string,
    builtIn: int,
    gamma, zero, one: float,
    maxSecs: int,
    zone1, zone2, zone3, zone4, zone5, ceiling, fitnessDays, fatigueDays, fitnessScale,
      fatigueScale: float,
  ]

proc modelsOf(db: DbConn, rows: seq[ModelRow]): seq[Model] {.raises: [StoreError].} =
  for r in rows:
    var m = Model(
      id: r.id,
      name: r.name,
      builtIn: r.builtIn == 1,
      gamma: r.gamma,
      zero: r.zero,
      one: r.one,
      maxSecs: r.maxSecs,
      zones: [r.zone1, r.zone2, r.zone3, r.zone4, r.zone5],
      ceiling: r.ceiling,
      fitnessDays: r.fitnessDays,
      fatigueDays: r.fatigueDays,
      fitnessScale: r.fitnessScale,
      fatigueScale: r.fatigueScale,
    )
    for p in db.query(
      string,
      "select pattern from ff_model_pattern where model_id = :id order by folded",
      id = r.id,
    ):
      m.patterns.add TagPattern(p) # (checked when it was written)
    result.add m

const order = " order by m.folded, m.id"

proc loadModels*(db: DbConn): seq[Model] {.raises: [StoreError].} =
  ## All the models, by name.
  modelsOf(db, db.query(ModelRow, "select " & columns & " from ff_model m" & order))

proc findModel*(db: DbConn, name: string): Option[Model] {.raises: [StoreError].} =
  ## The model called `name` (case and accents aside), if there is one.
  let found = modelsOf(
    db,
    db.query(
      ModelRow,
      "select " & columns & " from ff_model m where m.folded = :folded",
      folded = foldedName(name),
    ),
  )
  if found.len > 0:
    some(found[0])
  else:
    none(Model)

const inSelection =
  "m.id in (select model_id from model_selection where user_id = :user)"

proc selectedModels*(db: DbConn, user: UserId): seq[Model] {.raises: [StoreError].} =
  ## The user's models selection, by name.
  modelsOf(
    db,
    db.query(
      ModelRow,
      "select " & columns & " from ff_model m where " & inSelection & order,
      user = user,
    ),
  )

proc searchModels*(
    db: DbConn, user: UserId, patterns: seq[TagPattern], among: Among, also: bool
): seq[Model] {.raises: [StoreError].} =
  ## The models whose names match any of the patterns (all of them, if there are none), among every model or only the
  ## user's selection, with the selection added if `also`; by name.  The steps of a search (`subject/steps`).
  var found = sqlOf("1")
  if patterns.len > 0:
    found = sqlOf(
        "exists (select 1 from json_each(:patterns) p where m.folded glob p.value)"
      )
      .with("patterns", $(%patterns.mapIt(foldedPattern(it))))
  if among == amSelection:
    found = sqlOf("(") & found & sqlOf(" and " & inSelection & ")")
  if also:
    found = sqlOf("(") & found & sqlOf(" or " & inSelection & ")")
  let q = sqlOf("select " & columns & " from ff_model m where ") & found & sqlOf(order)
  modelsOf(
    db,
    db.query(ModelRow, (if among == amSelection or also: q.with("user", user)
      else: q)),
  )

proc replaceModelSelection*(
    db: DbConn, user: UserId, ids: seq[ModelId]
) {.raises: [StoreError].} =
  ## Make the models `ids` the user's models selection, in place of the one there was.
  db.execute("delete from model_selection where user_id = :user", user = user)
  for id in ids:
    db.execute(
      "insert into model_selection(user_id, model_id) values (:user, :id)",
      user = user,
      id = id,
    )

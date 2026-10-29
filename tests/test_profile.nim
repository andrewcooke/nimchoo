import std/[algorithm, sequtils, tables, unittest]
import nimchoo/profile

const path = "../choochoo/data/sdk/Profile.xlsx"
let p = loadProfile(path)

suite "profile":
  test "mapping type":
    let t = p.types["carry_exercise_name"]
    check t.kind == tkMapping
    check t.toValue["farmers_walk"] == 1
    check t.toName[1] == "farmers_walk"

  test "built-in and override types":
    check p.types["uint16"].kind == tkBase
    check p.types["bool"].kind == tkBool
    check p.types["timestamp_16"].kind == tkTimestamp16
    check p.types["date_time"].kind == tkDateTime
    check p.types["local_date_time"].kind == tkLocalDateTime
    check p.types["date_time"].base == btUint32

  test "message numbers":
    check p.messages["file_id"].number == 0
    check p.byNumber[p.messages["session"].number] == "session"

  test "dynamic field: session.total_cycles":
    let f = p.messages["session"].fields["total_cycles"]
    check f.kind == fkDynamic
    check f.refs == @["sport"]
    let sport = p.types["sport"]
    let strides = f.choices.filterIt(it.target == "total_strides")
    check strides.len >= 2
    check strides.allIt(it.refField == "sport")
    check sport.toValue["running"] in strides.mapIt(it.refValue)
    check sport.toValue["walking"] in strides.mapIt(it.refValue)

  test "dynamic field: workout_step 4 is target_value":
    let m = p.messages["workout_step"]
    let f = m.fields[m.byNumber[4]]
    check f.name == "target_value"
    check f.kind == fkDynamic
    check f.refs.sorted(system.cmp) == @["duration_type", "target_type"]

  test "composite field: record.speed -> enhanced_speed":
    let f = p.messages["record"].fields["speed"]
    check f.kind == fkComposite
    check f.components.len == 1
    check f.components[0].target == "enhanced_speed"
    check f.components[0].bits == 16
    check f.components[0].scale == 1000
    check f.components[0].units == "m/s"

  test "scale and offset: record.enhanced_altitude":
    let f = p.messages["record"].fields["enhanced_altitude"]
    check f.kind == fkPlain
    check f.scale == 5
    check f.offset == 500

  test "multi-component composite":
    let f = p.messages["record"].fields["compressed_speed_distance"]
    check f.kind == fkComposite
    check f.components.mapIt(it.target) == @["speed", "distance"]
    check f.components.mapIt(it.bits) == @[12, 12]
    check f.components.mapIt(it.scale) == @[100.0, 16.0]

  test "timestamp_16 override":
    check p.messages["monitoring"].fields["timestamp_16"].typeName ==
      "timestamp_16"

  test "profile is self-consistent":
    var numbers: seq[int]
    for m in p.messages.values:
      numbers.add m.number
      for f in m.fields.values:
        check f.typeName in p.types
        case f.kind
        of fkPlain: discard
        of fkComposite:
          for c in f.components: check c.target in m.fields
        of fkDynamic:
          for c in f.choices:
            check c.refField in m.fields
            check c.target in m.fields
    check numbers.deduplicate.len == numbers.len

  test "dynamic fields do not reference other dynamic fields":
    for m in p.messages.values:
      for f in m.fields.values:
        if f.kind == fkDynamic:
          for r in f.refs:
            if r in m.fields:
              check m.fields[r].kind != fkDynamic

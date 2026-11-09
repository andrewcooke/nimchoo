import ../../core/manifest

const package* = Package(
  depends: @[
    "db", "fit", "fold", "geo", "importer", "lookup", "names", "profiling", "selection",
    "ui",
  ],
  fragments: @[
    fragment("001-schema.sql"), # sector (with retired), effort, climbs_done
    fragment("002-name-number.sql"), # sector.name_n
    fragment("003-effort-index.sql"), # effort(activity_id)
  ],
)

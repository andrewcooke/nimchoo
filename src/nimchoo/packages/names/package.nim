import ../../core/manifest

const package* = Package(
  depends: @["cache", "db", "download", "fold", "geo", "ui", "zip"],
  fragments: @[
    fragment("001-schema.sql"), # country, coverage, feature
    fragment("002-country-cells.sql"), # country_cell, country_cell_done
    fragment("003-country-cell-index.sql"),
    fragment("004-landmark.sql"), # landmark: the author's own names for places
  ],
)

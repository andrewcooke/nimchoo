import ../../core/manifest

const package* = Package(depends: @["db"], fragments: @[
    fragment("001-schema.sql") # user_profile
  ])

## The modules of nch, in one place: which of them have database tables.  The
## schema is made by applying their fragments in this order, so a module comes
## after the modules whose tables it refers to.  (The user table, which
## everything refers to, belongs to the database code itself and is applied
## first, always.)  A new module with tables adds its `ddl` here.

import ./packages/climbs/ddl as climbsDdl
import ./packages/heartrate/ddl as heartrateDdl
import ./packages/importer/ddl as importerDdl
import ./packages/model/ddl as modelDdl
import ./packages/names/ddl as namesDdl
import ./packages/selection/ddl as selectionDdl
import ./packages/user/ddl as userDdl
import ./core/fragment

{.push raises: [].}

const allFragments*: seq[Fragment] =
  namesDdl.fragments & importerDdl.fragments & heartrateDdl.fragments &
  climbsDdl.fragments & selectionDdl.fragments & userDdl.fragments & modelDdl.fragments

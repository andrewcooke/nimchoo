## The modules of nch, in one place: which of them have database tables.  The
## schema is made by applying their fragments in this order, so a module comes
## after the modules whose tables it refers to.  (The user table, which
## everything refers to, belongs to the database code itself and is applied
## first, always.)  A new module with tables adds its `ddl` here.

import ./heartrate/ddl as heartrateDdl
import ./heartrate/step as heartrateStep
import ./importer/ddl as importerDdl
import ./model/ddl as modelDdl
import ./places/ddl as placesDdl
import ./selection/ddl as selectionDdl
import ./user/ddl as userDdl
import ./db/[channel, fragment]

{.push raises: [].}

const allFragments*: seq[Fragment] =
  placesDdl.fragments & importerDdl.fragments & heartrateDdl.fragments & selectionDdl.fragments &
  userDdl.fragments & modelDdl.fragments

let allImportSteps*: seq[ImportStep] = @[heartrateStep.heartrateStep]

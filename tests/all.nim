## Every test.  The files mirror src/nimchoo/: tests/<dir>/test_<file>.nim tests
## <dir>/<file>.nim (some cover a few neighbouring files); tests/support/ holds
## what they share.
{.push warning[UnusedImport]: off.}
import ./support/env, ./support/timing
import
  ./core/test_access,
  ./db/test_access,
  ./db/test_holding,
  ./db/test_orders,
  ./core/test_registry,
  ./core/test_inventory,
  ./core/test_imports,
  ./core/test_fmt,
  ./core/test_ownership,
  ./core/test_logfile,
  ./core/test_theme,
  ./core/test_globals,
  ./core/test_line,
  ./core/test_ruled,
  ./core/test_backticks,
  ./text/fold/test_fold,
  ./core/test_errors,
  ./test_structure,
  ./core/test_complete,
  ./test_introspect,
  ./test_completion
import ./cache/test_cache
import ./subject/test_subjects
import ./util/zip/test_zipbytes
import ./util/zip/test_fuzz as zipFuzz
import ./util/xlsx/test_xlsx
import ./util/xlsx/test_fuzz as xlsxFuzz
import ./util/zip/test_zipchild
import ./util/child/test_child
import ./text/templating/test_templating
import ./util/version/test_version
import ./util/atomic/test_atomic
import ./geo/[test_geo, test_cells, test_position]
import
  ./fit/[
    test_basetype, test_header, test_time, test_tokens, test_decode, test_sdkcsv,
    test_fuzz,
  ]
import ./fit/test_command
import ./util/bytes/test_bytes
import ./fit/test_load_errors
import ./fit/test_profilefuzz
import ./fit/test_load
import
  ./db/[
    test_statement, test_plans, test_functions, test_store, test_multirow,
    test_invariants, test_schema,
  ]
import ./db/test_command
import ./heartrate/test_step
import ./model/[test_calc, test_impulses]
import ./model/test_params
import ./model/test_completion as modelCompletion
import ./ff/test_curve
import ./ff/test_page
import ./ff/test_web
import ./ff/test_stats
import ./activities/test_delete
import ./cache/test_files
import ./cache/test_command
import
  ./importer/[
    test_extract,
    test_route,
    test_importer,
    test_visits,
    test_clean,
    test_series,
    test_batch,
    test_walk,
    test_pool,
    test_events,
    test_stretch,
    test_naming as importerNaming,
    test_describe as importerDescribe,
    test_fuzz as importerFuzz,
  ]
import ./importer/test_command as importCommandTests
import ./importer/test_params
import ./importer/test_display
import ./importer/test_logsink
import ./selection/[test_imported, test_selection]
import ./activities/test_ranges
import ./activities/test_criteria
import ./activities/test_completion as sportCompletion
import ./activities/test_table
import ./activities/test_command
import ./activities/test_mapframes
import ./activities/test_calendarframe
import ./activities/test_mapfeatures
import ./climbs/test_mapframes as climbsMapFrames
import ./climbs/test_mapfeatures as climbsMapFeatures
import ./calendar/test_calendar
import ./calendar/test_command as calendarCommandTests
import ./calendar/test_frames as calendarFrames
import ./map/test_params
import ./map/test_geojson
import ./map/test_page
import ./map/test_registry as mapRegistry
import ./map/test_command
import ./map/test_web
import ./util/args/test_args
import ./util/args/test_usage
import
  ./climbs/[
    test_detect,
    test_profile,
    test_match,
    test_overlap,
    test_pipeline,
    test_schema,
    test_work,
    test_report,
    test_attempts,
    test_imported as climbsImported,
    test_naming,
    test_display,
    test_duplicates,
    test_describe as climbsDescribe,
    test_edit as climbsEdit,
  ]
import ./climbs/test_criterion
import ./climbs/test_chosen
import ./climbs/test_found
import ./climbs/test_calendarframe
import ./climbs/test_completion as climbCompletion
import ./climbs/test_command
import ./climbs/test_params as climbsParams
import ./names/test_params as landmarkParams
import ./names/test_completion as landmarkCompletion
import ./names/test_command as landmarkCommand
import ./download/test_fetch
import
  ./names/[
    test_countryinfo, test_countries, test_features, test_climbpick, test_codes,
    test_climb, test_lookup, test_shape, test_activity, test_landmarks, test_places,
  ]
import
  ./web/[
    test_request,
    test_token,
    test_handler,
    test_pages,
    test_libraries,
    test_workers,
    test_fuzz as webFuzz,
  ]
import ./user/test_session
import ./user/test_wipe
import ./user/test_params
import ./user/test_completion as userCompletion
import ./user/test_command
import ./confirm/test_confirm
import ./importer/test_count
import ./bundle/test_unpack
import ./themes/test_choose
import
  ./ui/[test_units, test_style, test_live, test_vocabulary, test_interval, test_markup]
import ./log/test_lines
import ./log/test_command
{.pop.}

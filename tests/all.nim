## Every test.  The files mirror src/nimchoo/: tests/<dir>/test_<file>.nim tests
## <dir>/<file>.nim (some cover a few neighbouring files); tests/support/ holds
## what they share.
{.push warning[UnusedImport]: off.}
import ./support/env, ./support/timing
import
  ./core/test_registry,
  ./core/test_imports,
  ./core/test_ownership,
  ./core/test_logfile,
  ./text/fold/test_fold,
  ./core/test_errors,
  ./test_structure
import ./cache/test_cache
import ./util/zip/test_zipbytes
import ./util/xlsx/test_xlsx
import ./util/zip/test_zipchild
import ./util/child/test_child
import ./text/templating/test_templating
import ./util/version/test_version
import ./text/proquint/test_proquint
import ./util/atomic/test_atomic
import ./geo/test_geo
import
  ./fit/[
    test_basetype, test_header, test_time, test_tokens, test_decode, test_sdkcsv,
    test_fuzz,
  ]
import ./commands/fitcmd/test_command
import ./util/bytes/test_bytes
import ./fit/test_load_errors
import ./fit/test_load
import
  ./db/[
    test_statement, test_plans, test_store, test_multirow, test_invariants, test_schema
  ]
import ./commands/dbcmd/test_command
import ./heartrate/test_step
import ./model/[test_calc, test_impulses]
import ./commands/modelscmd/test_params
import ./ff/[test_curve, test_page, test_web, test_stats]
import ./delete/test_delete
import ./cache/test_files
import ./commands/cachecmd/test_command
import
  ./importer/[
    test_extract,
    test_route,
    test_importer,
    test_command,
    test_batch,
    test_pool,
    test_events,
    test_display,
    test_logsink,
    test_stretch,
    test_naming as importerNaming,
    test_describe as importerDescribe,
  ]
import
  ./selection/[
    test_bits, test_ranges, test_criteria, test_table, test_command, test_selection,
    test_calendar,
  ]
import ./map/[test_params, test_lines, test_page, test_command, test_web]
import ./cli/test_catalog
import ./util/args/test_args
import
  ./climbs/[
    test_detect,
    test_profile,
    test_match,
    test_pipeline,
    test_schema,
    test_work,
    test_report,
    test_attempts,
    test_naming,
    test_display,
    test_duplicates,
    test_describe as climbsDescribe,
    test_edit as climbsEdit,
  ]
import ./commands/climbscmd/test_command
import ./commands/climbscmd/test_params as climbsParams
import ./commands/landmarkscmd/test_params as landmarkParams
import ./commands/landmarkscmd/test_command as landmarkCommand
import ./download/test_fetch
import
  ./names/[
    test_countryinfo, test_countries, test_features, test_climbpick, test_climb,
    test_lookup, test_shape, test_activity, test_landmarks,
  ]
import
  ./web/
    [test_request, test_token, test_handler, test_pages, test_libraries, test_workers]
import ./user/test_wipe
import ./commands/userscmd/test_params
import ./commands/userscmd/test_command
import ./confirm/test_confirm
import ./importer/test_count
import ./bundle/test_unpack
import
  ./ui/[test_units, test_style, test_live, test_vocabulary, test_interval, test_palette]
import ./commands/logcmd/test_lines
import ./commands/logcmd/test_command
{.pop.}

## Every test.  The files mirror src/nimchoo/: tests/<dir>/test_<file>.nim tests
## <dir>/<file>.nim (some cover a few neighbouring files); tests/support/ holds
## what they share.
{.push warning[UnusedImport]: off.}
import ./support/env, ./support/timing
import ./test_zipbytes, ./test_xlsx, ./test_errors, ./test_structure, ./test_cache, ./test_geo, ./test_templating, ./test_version
import ./fit/[test_bytes, test_basetype, test_header, test_time, test_tokens, test_decode,
              test_command, test_sdkcsv]
import ./profile/[test_load, test_load_errors]
import ./db/[test_store, test_multirow, test_command]
import ./heartrate/test_step
import ./model/[test_calc, test_params, test_impulses]
import ./ff/[test_curve, test_page, test_web, test_stats]
import ./delete/test_delete
import ./cache/[test_command, test_files]
import ./importer/[test_extract, test_route, test_importer, test_command, test_batch, test_pool, test_events,
                   test_display, test_logsink, test_naming as importerNaming, test_describe as importerDescribe]
import ./selection/[test_fold, test_ranges, test_criteria, test_table, test_command, test_selection, test_calendar]
import ./heatmap/[test_params, test_lines, test_page, test_command, test_web]
import ./cli/test_args
import ./climbs/[test_detect, test_profile, test_match, test_pipeline, test_schema, test_work, test_report, test_attempts, test_command, test_naming, test_display, test_duplicates, test_describe as climbsDescribe,
                    test_params as climbsParams, test_edit as climbsEdit]
import ./landmark/[test_params as landmarkParams, test_landmarks, test_command as landmarkCommand]
import ./download/test_fetch
import ./names/[test_countryinfo, test_countries, test_features, test_climbpick, test_climb, test_lookup, test_shape, test_activity]
import ./serve/[test_request, test_token, test_handler, test_pages, test_libraries]
import ./user/[test_params, test_command, test_wipe]
import ./bundle/test_unpack
import ./ui/[test_units, test_style, test_live, test_logfile, test_vocabulary, test_interval, test_palette]
import ./log/[test_lines, test_command]
{.pop.}

## Every test.  The files mirror src/nimchoo/: tests/<dir>/test_<file>.nim tests
## <dir>/<file>.nim (some cover a few neighbouring files); tests/support/ holds
## what they share.
{.push warning[UnusedImport]: off.}
import ./support/env, ./support/timing
import ./test_xlsx, ./test_errors, ./test_structure, ./test_cache, ./test_templating, ./test_version
import ./fit/[test_bytes, test_basetype, test_header, test_time, test_tokens, test_decode,
              test_command, test_sdkcsv]
import ./profile/[test_load, test_load_errors]
import ./db/[test_store, test_multirow]
import ./heartrate/test_step
import ./model/[test_calc, test_params, test_impulses]
import ./ff/[test_curve, test_page, test_web, test_stats]
import ./empty/[test_command, test_cachefiles]
import ./importer/[test_extract, test_route, test_importer, test_command, test_batch, test_pool, test_events,
                   test_display, test_logsink]
import ./selection/[test_ranges, test_criteria, test_table, test_command, test_selection, test_calendar]
import ./heatmap/[test_params, test_lines, test_page, test_command, test_web]
import ./cli/test_args
import ./climbs/[test_detect, test_profile, test_match, test_pipeline]
import ./serve/[test_request, test_token, test_handler, test_pages, test_libraries]
import ./places/[test_data, test_seed, test_reload]
import ./user/[test_params, test_command, test_wipe]
import ./bundle/test_unpack
import ./ui/[test_style, test_live, test_logfile, test_vocabulary, test_interval, test_palette]
import ./log/[test_lines, test_command]
{.pop.}

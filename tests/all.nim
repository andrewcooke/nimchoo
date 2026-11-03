## Every test.  The files mirror src/nimchoo/: tests/<dir>/test_<file>.nim tests
## <dir>/<file>.nim (some cover a few neighbouring files); tests/support/ holds
## what they share.
{.push warning[UnusedImport]: off.}
import ./test_xlsx, ./test_errors, ./test_structure, ./test_cache
import ./fit/[test_bytes, test_basetype, test_header, test_time, test_tokens, test_decode,
              test_command, test_sdkcsv]
import ./profile/[test_load, test_load_errors]
import ./db/test_store
import ./heartrate/test_step
import ./model/[test_calc, test_params, test_impulses]
import ./ff/[test_curve, test_page, test_web, test_stats]
import ./destroy/test_command
import ./importer/[test_extract, test_route, test_importer, test_command, test_batch, test_events,
                   test_display, test_logsink]
import ./selection/[test_ranges, test_criteria, test_table, test_command, test_selection]
import ./heatmap/[test_params, test_lines, test_page, test_command, test_web]
import ./serve/[test_request, test_token, test_handler, test_pages]
import ./places/[test_data, test_seed]
import ./user/[test_params, test_command]
import ./ui/[test_style, test_live, test_logfile, test_vocabulary, test_interval]
import ./log/[test_lines, test_command]
{.pop.}

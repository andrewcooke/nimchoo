#!/bin/sh
# Claude Code PostToolUse hook: format a .nim file with nph after Edit or Write, so that code is in the
# project's format as it is written (nimble test refuses unformatted files).  Reads the hook's JSON on stdin.
f=$(jq -r '.tool_input.file_path // empty')
case "$f" in
  *.nim) nph "$f" >/dev/null 2>&1 || true ;;
esac
exit 0

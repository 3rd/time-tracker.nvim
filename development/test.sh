#!/usr/bin/env bash
set -uf -o pipefail
IFS=$'\n\t'

STATUS=0
function run_all_tests() {
  FILES=$(find . -name "*_spec.lua" -type f)

  for f in $FILES; do
    echo "-> $f"
    nvim -u NONE +"luafile development/bootstrap.lua" -l "$f" +"luafile development/test_post.lua" "$@"
    STATUS=$((STATUS + $?))
  done
  echo ""
}

if [[ "$*" == *"--watch"* ]]; then
  watchexec --stop-timeout=0 --no-process-group --stop-signal SIGKILL -e ".lua" -r -c clear -w . --ignore-nothing -- ./development/test.sh
else
  run_all_tests "$@"
fi

exit $STATUS

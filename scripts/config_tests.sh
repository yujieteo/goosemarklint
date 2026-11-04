#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
bin=$1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

for d in "$root"/test/config/*/; do
  name=$(basename "$d")
  status=0
  (cd "$d/pass" && "$bin" check .) >"$work/out" 2>&1 || status=$?
  if [ "$status" -ne 0 ] || [ -s "$work/out" ]; then
    cat "$work/out"
    echo "config_tests: $name/pass exited $status, want 0 with no output"
    exit 1
  fi
  status=0
  (cd "$d/fail" && "$bin" check .) >"$work/out" 2>&1 || status=$?
  if [ "$status" -ne 1 ]; then
    cat "$work/out"
    echo "config_tests: $name/fail exited $status, want 1"
    exit 1
  fi
done

status=0
printf 'disable\tno-such-rule\n' >"$work/.goosemarklint"
printf '# Doc\n\nA line.\n' >"$work/doc.md"
(cd "$work" && "$bin" check .) >"$work/out" 2>&1 || status=$?
if [ "$status" -ne 2 ]; then
  echo "config_tests: an unknown rule in disable exited $status, want 2"
  exit 1
fi

version=$("$bin" --version)
if ! grep -q "^let VERSION = \"${version#goosemarklint }\";" "$root/src/main.goose" || [ "${version%% *}" != goosemarklint ]; then
  echo "config_tests: --version printed '$version'"
  exit 1
fi
echo "config_tests: exclude, disable and --version pass"

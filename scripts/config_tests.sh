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

abs="$work/abs"
mkdir -p "$abs/vendor"
printf '# Vendor\n\nThe tool does not whitelist this; it fails.\n' >"$abs/vendor/bad.md"
printf 'exclude\t./vendor/\n' >"$abs/.goosemarklint"
for p in "$abs/vendor/bad.md" ./vendor/bad.md; do
  status=0
  (cd "$abs" && "$bin" check "$p") >"$work/out" 2>&1 || status=$?
  if [ "$status" -ne 0 ] || [ -s "$work/out" ]; then
    cat "$work/out"
    echo "config_tests: exclude ./vendor/ with $p exited $status, want 0 with no output"
    exit 1
  fi
done

version=$("$bin" --version)
if ! [[ "$version" =~ ^goosemarklint\ [0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "config_tests: --version printed '$version'"
  exit 1
fi
echo "config_tests: exclude, disable and --version pass"

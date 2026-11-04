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
absdir=$(cd "$abs" && pwd -P)
for p in "$absdir/vendor/bad.md" ./vendor/bad.md; do
  status=0
  (cd "$abs" && PWD=/nonexistent "$bin" check "$p") >"$work/out" 2>&1 || status=$?
  if [ "$status" -ne 0 ] || [ -s "$work/out" ]; then
    cat "$work/out"
    echo "config_tests: exclude ./vendor/ with $p exited $status, want 0 with no output"
    exit 1
  fi
done

fmtdir="$work/fmt"
mkdir -p "$fmtdir/vendor"
printf 'First sentence. Second sentence.\n' >"$fmtdir/vendor/bad.md"
cp "$fmtdir/vendor/bad.md" "$fmtdir/doc.md"
cp "$fmtdir/vendor/bad.md" "$work/original.md"
printf 'exclude\tvendor/\n' >"$fmtdir/.goosemarklint"
status=0
(cd "$fmtdir" && PWD=/nonexistent "$bin" fmt .) >"$work/out" 2>&1 || status=$?
if [ "$status" -ne 0 ] || cmp -s "$fmtdir/doc.md" "$work/original.md" || ! cmp -s "$fmtdir/vendor/bad.md" "$work/original.md"; then
  cat "$work/out"
  echo "config_tests: fmt with exclude vendor/ exited $status, or did not format doc.md and keep vendor/bad.md"
  exit 1
fi

sentence="The tool checks the markdown files of a repo for style."
lone="$work/lone"
mkdir -p "$lone/pass"
printf '# Lone\n\n%s\n' "$sentence" >"$lone/pass/doc.md"
printf '# Other\n\n%s\n' "$sentence" >"$lone/other.md"
(cd "$lone" && PWD=/nonexistent "$bin" check .) >"$work/out" 2>&1 || true
if ! grep -q 'repeated-fact: warning' "$work/out"; then
  cat "$work/out"
  echo "config_tests: a pass folder with no sibling fail folder gave no repeated-fact warning"
  exit 1
fi

sibling="$work/sibling"
mkdir -p "$sibling/pass" "$sibling/fail"
printf '# Pass\n\n%s\n' "$sentence" >"$sibling/pass/doc.md"
printf '# Fail\n\n%s\n' "$sentence" >"$sibling/fail/doc.md"
status=0
(cd "$sibling" && PWD=/nonexistent "$bin" check .) >"$work/out" 2>&1 || status=$?
if [ "$status" -ne 0 ] || [ -s "$work/out" ]; then
  cat "$work/out"
  echo "config_tests: a pass folder with a sibling fail folder exited $status, want 0 with no output"
  exit 1
fi

version=$("$bin" --version)
if ! [[ "$version" =~ ^goosemarklint\ [0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "config_tests: --version printed '$version'"
  exit 1
fi
echo "config_tests: exclude, disable and --version pass"

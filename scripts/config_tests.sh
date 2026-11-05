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
status=0
(cd "$abs" && "$bin" check ./vendor/bad.md) >"$work/out" 2>&1 || status=$?
if [ "$status" -ne 0 ] || [ -s "$work/out" ]; then
  cat "$work/out"
  echo "config_tests: exclude ./vendor/ with ./vendor/bad.md exited $status, want 0 with no output"
  exit 1
fi

fmtdir="$work/fmt"
mkdir -p "$fmtdir/vendor"
printf 'First sentence. Second sentence.\n' >"$fmtdir/vendor/bad.md"
cp "$fmtdir/vendor/bad.md" "$fmtdir/doc.md"
cp "$fmtdir/vendor/bad.md" "$work/original.md"
printf 'exclude\tvendor/\n' >"$fmtdir/.goosemarklint"
status=0
(cd "$fmtdir" && "$bin" fmt .) >"$work/out" 2>&1 || status=$?
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
(cd "$lone" && "$bin" check .) >"$work/out" 2>&1 || true
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
(cd "$sibling" && "$bin" check .) >"$work/out" 2>&1 || status=$?
if [ "$status" -ne 0 ] || [ -s "$work/out" ]; then
  cat "$work/out"
  echo "config_tests: a pass folder with a sibling fail folder exited $status, want 0 with no output"
  exit 1
fi

outer="$work/outer"
mkdir -p "$outer/fail" "$outer/pass/repo"
printf '# A\n\n%s\n' "$sentence" >"$outer/pass/repo/a.md"
printf '# B\n\n%s\n' "$sentence" >"$outer/pass/repo/b.md"
(cd "$outer" && "$bin" check pass/repo) >"$work/out" 2>&1 || true
if ! grep -q 'repeated-fact: warning' "$work/out"; then
  cat "$work/out"
  echo "config_tests: a repo under a pass folder with a sibling fail folder gave no repeated-fact warning"
  exit 1
fi
(cd "$outer" && "$bin" check pass/repo/a.md pass/repo/b.md) >"$work/out" 2>&1 || true
if ! grep -q 'repeated-fact: warning' "$work/out"; then
  cat "$work/out"
  echo "config_tests: file arguments under a pass folder with a sibling fail folder gave no repeated-fact warning"
  exit 1
fi

syntax="$work/syntax"
mkdir -p "$syntax/folder space"
printf '# Doc\n\nBad phrase; keep this.\n' >"$syntax/doc.md"
printf '# Doc\n\nBad phrase.\n' >"$syntax/folder space/doc.md"
printf '%s\n' 'allow = ["finding", "other"]' 'ban = [["bad phrase", "better phrase"]]' \
  'exclude = [' '  "folder space/"' ']' 'disable = ["ste-semicolon"]' >"$syntax/.goosemarklint"
status=0
(cd "$syntax" && "$bin" check .) >"$work/out" 2>&1 || status=$?
if [ "$status" -ne 1 ] || ! grep -q 'use "better phrase"' "$work/out" || grep -qE 'ste-semicolon|folder space' "$work/out"; then
  cat "$work/out"
  echo "config_tests: key/value lists did not apply"
  exit 1
fi
status=0
(cd "$syntax" && "$bin" fmt --check 'folder space/doc.md') >"$work/out" 2>&1 || status=$?
if [ "$status" -ne 0 ] || [ -s "$work/out" ]; then
  cat "$work/out"
  echo "config_tests: fmt did not honor key/value exclusion"
  exit 1
fi
mkdir -p "$syntax/generated"
printf 'allow = ["unusual"]\nban = [["unusual", "normal"]]\ngenerated = ["generated/"]\n' >"$syntax/.goosemarklint"
printf '# Doc\n\nUnusual wording helps the reader understand how this command works.\n' >"$syntax/doc.md"
cp "$syntax/doc.md" "$syntax/generated/doc.md"
status=0
(cd "$syntax" && "$bin" check doc.md generated/doc.md) >"$work/out" 2>&1 || status=$?
if [ "$status" -ne 0 ] || [ -s "$work/out" ]; then
  cat "$work/out"
  echo "config_tests: key/value allow or generated failed"
  exit 1
fi
for invalid in 'ban = [["bad", ""]]' 'allow = [1]' 'disable = ["no-such-rule"]' 'exclude = ["folder",]' 'ban = [["bad"]]'; do
  printf '%s\n' "$invalid" >"$syntax/.goosemarklint"
  status=0
  (cd "$syntax" && "$bin" check .) >"$work/out" 2>&1 || status=$?
  if [ "$status" -ne 2 ]; then
    cat "$work/out"
    echo "config_tests: invalid entry accepted: $invalid"
    exit 1
  fi
done
mkdir -p "$syntax/a=b"
printf 'exclude\ta=b/\n' >"$syntax/.goosemarklint"
printf '# Doc\n\nA line; with a semicolon.\n' >"$syntax/a=b/doc.md"
status=0
(cd "$syntax" && "$bin" check 'a=b/doc.md') >"$work/out" 2>&1 || status=$?
if [ "$status" -ne 0 ] || [ -s "$work/out" ]; then
  cat "$work/out"
  echo "config_tests: legacy tab entry with equals failed"
  exit 1
fi

version=$("$bin" --version)
if ! [[ "$version" =~ ^goosemarklint\ [0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "config_tests: --version printed '$version'"
  exit 1
fi
echo "config_tests: exclude, disable and --version pass"

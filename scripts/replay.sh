#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
accept=no
if [ "${1:-}" = --accept ]; then accept=yes; fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

main=$(git -C "$root" rev-parse -q --verify main || git -C "$root" rev-parse -q --verify origin/main) || {
  echo "replay: no main or origin/main branch to compare with"
  exit 1
}
base=$(git -C "$root" merge-base HEAD "$main")
mkdir "$work/base"
git -C "$root" archive "$base" | tar -x -C "$work/base"
if [ ! -e "$work/base/src/main.goose" ]; then
  echo "replay: base ${base:0:12} has no parser, so there is no output to compare"
  exit 0
fi
goose build -q "$work/base/src/main.goose" -o "$work/base.bin" >/dev/null
goose build -q "$root/src/main.goose" -o "$work/branch.bin" >/dev/null

files=("$root"/test/corpus/*.md)
limit=$((${#files[@]} / 5))
changed=0
for f in "${files[@]}"; do
  name=$(basename "$f")
  { "$work/base.bin" tree "$f" || echo "exit $?"; } >"$work/base.out" 2>&1
  { "$work/branch.bin" tree "$f" || echo "exit $?"; } >"$work/branch.out" 2>&1
  if ! diff -u --label "base/$name" --label "branch/$name" "$work/base.out" "$work/branch.out"; then
    changed=$((changed + 1))
    if [ "$changed" -gt "$limit" ]; then
      echo "replay: large change, more than 20% of ${#files[@]} outputs differ, stopped early"
      [ "$accept" = yes ] && exit 0
      exit 1
    fi
  fi
done
echo "replay: $changed of ${#files[@]} outputs differ from base ${base:0:12}"
if [ "$changed" -gt 0 ] && [ "$accept" != yes ]; then
  echo "replay: read the diff, then run again with --accept to accept it"
  exit 1
fi

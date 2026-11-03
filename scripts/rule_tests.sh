#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
bin=$1
accept=no
if [ "${2:-}" = --accept ]; then accept=yes; fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

run() {
  local want=$1 dir=$2 status=0
  shift 2
  (cd "$dir" && "$bin" check "$@") >"$work/out" 2>&1 || status=$?
  if [ "$want" = findings ]; then
    want=1
    if [ -s "$work/out" ] && ! grep -qv ": warning: " "$work/out"; then want=0; fi
  fi
  if [ "$status" -ne "$want" ]; then
    cat "$work/out"
    echo "rule_tests: check $* in $dir exited $status, want $want"
    exit 1
  fi
}

mapfile -t rules < <("$bin" rules)
mapfile -t dirs < <(find "$root/test/rules" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
mapfile -t sorted < <(printf '%s\n' "${rules[@]}" | sort)
if [ "${dirs[*]}" != "${sorted[*]}" ]; then
  echo "rule_tests: test/rules has [${dirs[*]}], the rules are [${sorted[*]}]"
  exit 1
fi
for r in "${rules[@]}"; do
  run 0 "$root/test/rules" "$r/pass"
  run findings "$root/test/rules" "$r/fail"
  if grep -v ": $r: " "$work/out"; then
    echo "rule_tests: $r/fail gives a finding of another rule"
    exit 1
  fi
  if ! grep -q "\`$r\`" "$root/README.md"; then
    echo "rule_tests: README.md does not name the rule $r"
    exit 1
  fi
done
run 0 "$root" README.md

changed=0
for name in rules corpus; do
  if [ "$name" = rules ]; then run 1 "$root/test/rules" .; else run 1 "$root/test/corpus" .; fi
  if ! diff -u --label "test/$name.expect" --label "branch/$name" "$root/test/$name.expect" "$work/out"; then
    changed=$((changed + 1))
    if [ "$accept" = yes ]; then cp "$work/out" "$root/test/$name.expect"; fi
  fi
done
echo "rule_tests: ${#rules[@]} rules pass, $changed of 2 saved outputs differ"
if [ "$changed" -gt 0 ] && [ "$accept" != yes ]; then
  echo "rule_tests: read the diff, then run again with --accept to accept it"
  exit 1
fi

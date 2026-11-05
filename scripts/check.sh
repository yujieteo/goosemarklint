#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
roots=(src/main.goose src/spec_test.goose tools/lint.goose)

goose format --check "$root/src" "$root/tools"
for p in "${roots[@]}"; do
  goose build -q "$root/$p" -o "$out/$(basename "$p" .goose)" >/dev/null
  goose check -q -O0 --specs "$root/$p" >>"$out/specs.txt"
done

"$out/spec_test" \
  cm "$root/test/spec/commonmark-0.31.2.txt" \
  gfm "$root/test/spec/gfm-0.29.txt" \
  ext "$root/test/spec/extensions.txt"

mapfile -t sources < <(git -C "$root" ls-files -co --exclude-standard '*.goose' '*.sh')
"$out/lint" "$out/specs.txt" "${sources[@]/#/$root/}"
for f in $(git -C "$root" ls-files -co --exclude-standard '*.py'); do
  if python3 -I -m tokenize "$root/$f" | awk '$2 == "COMMENT" { found = 1; print } END { exit !found }'; then
    echo "$f: comment"
    exit 1
  fi
done

for m in $(git -C "$root" ls-files -co --exclude-standard '*.sm.md' ':!test/corpus' ':!test/rules'); do
  mapfile -t cited < <(awk -F '|' '
    !/^\|/ { col = 0; next }
    !col { for (i = 2; i < NF; i++) { h = $i; gsub(/ /, "", h); if (h == "source") col = i } next }
    $col !~ /^ *-+ *$/ { v = $col; gsub(/ /, "", v); print v }
  ' "$root/$m")
  if [ "${#cited[@]}" -eq 0 ]; then
    echo "$m: no machine table with a source column"
    exit 1
  fi
  for f in "${cited[@]}"; do
    if ! grep -Eqh "^fn ${f}\(" "${sources[@]/#/$root/}"; then
      echo "$m: no fn $f"
      exit 1
    fi
  done
done

tail -n +2 "$root/data/sources.tsv" | awk -F '\t' -v root="$root" '{ print $2 "  " root "/" $1 }' >"$out/sources.sha256"
sha256sum --check --quiet "$out/sources.sha256"

"$root/scripts/rule_tests.sh" "$out/main" "$@"
"$root/scripts/fmt_tests.sh" "$out/main" "$@"
"$root/scripts/config_tests.sh" "$out/main"
"$root/scripts/replay.sh" "$@"
echo "check: all checks passed"

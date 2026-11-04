#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
bin=$1
accept=no
if [ "${2:-}" = --accept ]; then accept=yes; fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
not_layout='MD033|MD034|MD040'

cp -r "$root/test/corpus" "$work/corpus"
cp -r "$root/test/fmt" "$work/corpus/fmt"
"$bin" fmt "$work/corpus"
if ! "$bin" fmt --check "$work/corpus"; then
  echo "fmt_tests: fmt of the formatted corpus changes it again"
  exit 1
fi
(cd "$work/corpus" && "$bin" check .) >"$work/check" || true
if grep -E ': MD[0-9]+: ' "$work/check" | grep -Ev ": ($not_layout): "; then
  echo "fmt_tests: the formatted corpus has layout findings"
  exit 1
fi

(cd "$work/corpus" && find . -name '*.md' | sort | while read -r f; do
  echo "==> ${f#./} <=="
  cat "$f"
done) >"$work/fmt"
if diff -u --label test/fmt.expect --label branch/fmt "$root/test/fmt.expect" "$work/fmt"; then
  echo "fmt_tests: the formatted corpus is the same as test/fmt.expect"
  exit 0
fi
if [ "$accept" = yes ]; then
  cp "$work/fmt" "$root/test/fmt.expect"
  exit 0
fi
echo "fmt_tests: read the diff, then run again with --accept to accept it"
exit 1

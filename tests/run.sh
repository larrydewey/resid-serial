#!/usr/bin/env bash
# Run resid-serial's tests: build tools/resid-derive, regenerate the derive
# test model, then compile each test program and compare its output with
# the golden NAME.out beside it.
#
#   tests/run.sh            run everything
#   tests/run.sh --update   rewrite the .out files from the current output
#
# RESIDC picks the compiler (default: residc on PATH, else ~/.resid/bin/residc).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESIDC="${RESIDC:-$(command -v residc || echo "$HOME/.resid/bin/residc")}"
UPDATE=0
[ "${1:-}" = "--update" ] && UPDATE=1
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export RESID_MEM_LIMIT="${RESID_MEM_LIMIT:-6000}"

pass=0
fail=0

compile() { # compile <src> <out-bin>
    "$RESIDC" "$1" -o "$2" --profile debug > "$WORK/compile.log" 2>&1 || {
        grep -v '^OK \|^note:\|^typecheck OK\|^wrote ' "$WORK/compile.log" | head -20
        return 1
    }
}

compile "$ROOT/tools/resid-derive.resid" "$WORK/resid-derive" || { echo "FAIL build tools/resid-derive"; exit 1; }
"$WORK/resid-derive" --lib ../../src "$ROOT/tests/derive/model.resid" > /dev/null || { echo "FAIL resid-derive on tests/derive/model.resid"; exit 1; }
"$WORK/resid-derive" --lib ../../src "$ROOT/tests/derive/options.resid" > /dev/null || { echo "FAIL resid-derive on tests/derive/options.resid"; exit 1; }
"$WORK/resid-derive" --inplace "$ROOT/tests/readme.resid" > /dev/null || { echo "FAIL resid-derive --inplace on tests/readme.resid"; exit 1; }
# --inplace twice: the second run must not change the file.
"$WORK/resid-derive" --inplace "$ROOT/tests/derive/inplace_app.resid" > /dev/null || { echo "FAIL resid-derive --inplace"; exit 1; }
cp "$ROOT/tests/derive/inplace_app.resid" "$WORK/inplace_once.resid"
"$WORK/resid-derive" --inplace "$ROOT/tests/derive/inplace_app.resid" > /dev/null
if cmp -s "$WORK/inplace_once.resid" "$ROOT/tests/derive/inplace_app.resid"; then echo "PASS resid-derive --inplace is idempotent"; pass=$((pass + 1)); else echo "FAIL resid-derive --inplace changed the file on a second run"; fail=$((fail + 1)); fi

# The command line and diagnostics of resid-derive.
if [ "$UPDATE" = 1 ]; then
    "$ROOT/tests/derive/cli.sh" "$WORK/resid-derive" "$RESIDC" "$WORK/cli" > "$ROOT/tests/derive/cli.out" 2>&1
    echo "UPDATED derive/cli.sh"
elif "$ROOT/tests/derive/cli.sh" "$WORK/resid-derive" "$RESIDC" "$WORK/cli" > "$WORK/cli.txt" 2>&1 && diff -u "$ROOT/tests/derive/cli.out" "$WORK/cli.txt" > "$WORK/diff.txt"; then
    echo "PASS derive/cli.sh"
    pass=$((pass + 1))
else
    echo "FAIL derive/cli.sh"
    head -40 "$WORK/diff.txt"
    fail=$((fail + 1))
fi

# Every test program except the shared check module.
for src in "$ROOT"/tests/*.resid "$ROOT"/tests/derive/derive_test.resid "$ROOT"/tests/formats/compact_test.resid "$ROOT"/tests/derive/inplace_app.resid "$ROOT"/tests/derive/options_test.resid; do
    [ "$(basename "$src")" = "check.resid" ] && continue
    name="${src#"$ROOT"/tests/}"
    want="${src%.resid}.out"
    bin="$WORK/$(basename "${src%.resid}")"
    if ! compile "$src" "$bin"; then
        echo "FAIL $name (compile)"
        fail=$((fail + 1))
        continue
    fi
    # The exit status is part of the output, so a crash cannot pass.
    "$bin" > "$WORK/got.txt" 2>&1
    echo "exit $?" >> "$WORK/got.txt"
    if [ "$UPDATE" = 1 ]; then
        cp "$WORK/got.txt" "$want"
        echo "UPDATED $name"
    elif diff -u "$want" "$WORK/got.txt" > "$WORK/diff.txt"; then
        echo "PASS $name"
        pass=$((pass + 1))
    else
        echo "FAIL $name"
        head -40 "$WORK/diff.txt"
        fail=$((fail + 1))
    fi
done

[ "$UPDATE" = 1 ] && exit 0
echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]

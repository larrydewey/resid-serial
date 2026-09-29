#!/usr/bin/env bash
# resid-derive's command line and diagnostics, and the compile-time checks
# its output relies on. Prints a transcript that tests/run.sh compares with
# cli.out.
#   cli.sh RESID_DERIVE RESIDC WORKDIR
set -uo pipefail
RD="$1"; RESIDC="$2"; W="$3"
SRC="$(cd "$(dirname "$0")/../.." && pwd)/src"
mkdir -p "$W" && cd "$W" || exit 1

run() { # run NAME CMD...: exit status, then stdout and stderr
    local name="$1"; shift
    echo "== $name"
    "$@" > out.txt 2> err.txt
    echo "exit $?"
    cat out.txt err.txt
}

# Command line.
run "no arguments" "$RD"
run "unknown option" "$RD" --what x.resid
run "missing file" "$RD" nope.resid

# Diagnostics, one per file.
case_file() { printf "$2" > "$1.resid"; run "$1" "$RD" "$1.resid"; }
case_file closure_field '//@ serial\ntype C = { Int closure(Int) f; };\n'
case_file closure_payload '//@ serial\ntype Z = A | B(Int closure(Int));\n'
case_file no_zero_value '//@ serial\ntype Inner = { Int x; };\n//@ serial\ntype D = { Inner i; };   //@ default\n'
case_file unknown_rule '//@ serial(rename_all = "Title Case")\ntype R = { Int a; };\n'
case_file unknown_container_option '//@ serial(renam = "X")\ntype A1 = { Int a; };\n'
case_file unknown_field_option '//@ serial\ntype A2 = { Int a; };   //@ defualt\n'
case_file unknown_variant_option '//@ serial\ntype A3 = X3 | Y3;   //@ flatten\n'
case_file tag_on_record '//@ serial(tag = "t")\ntype A4 = { Int a; };\n'
case_file transparent_on_sum '//@ serial(transparent)\ntype A5 = X5 | Y5(Int);\n'
case_file transparent_two_fields '//@ serial(transparent)\ntype T2 = { Int a; Int b; };\n'
case_file content_without_tag '//@ serial(content = "c")\ntype A6 = X6 | Y6(Int);\n'
case_file tag_without_name '//@ serial(tag)\ntype A7 = X7 | Y7(Int);\n'
case_file untagged_with_tag '//@ serial(tag = "t", untagged)\ntype A8 = X8 | Y8(Int);\n'
case_file deny_with_flatten '//@ serial(deny_unknown_fields)\ntype A9 = { Int a; Q q; };   //@ flatten\n'
case_file unterminated '//@ serial\ntype U = { Int a;\n'
case_file missing_semicolon '//@ serial\ntype M = { Int a Int b; };\n'
case_file unannotated_malformed 'type Weird\nInt main() { return 0; }\n'
cat unannotated_malformed_serial.resid

# Output placement: -o, --lib with and without a trailing slash.
printf '//@ serial\ntype P = { Int a; };\n' > p.resid
run "-o and --lib dir/" "$RD" -o custom.resid --lib lib/ p.resid
head -4 custom.resid
run "--lib dir" "$RD" --lib lib p.resid
head -4 p_serial.resid

# --inplace: appends, then replaces its region when the annotations change.
printf 'import "%s/serial.resid";\n\n//@ serial\ntype Q = { Int a; };\n' "$SRC" > inplace.resid
run "--inplace first run" "$RD" --inplace inplace.resid
grep -c "resid-derive: begin" inplace.resid
sed -i 's/type Q = { Int a; };/type Q = { Int a; Int b; };/' inplace.resid
run "--inplace after an edit" "$RD" --inplace inplace.resid
grep -c "resid-derive: begin" inplace.resid
grep -c '"b"' inplace.resid

# A skipped closure field compiles and keeps its default.
cat > closure_skip.resid <<RESID
import "$SRC/serial.resid";
import "$SRC/value.resid";
//@ serial
type CS = { Int a; Int closure(Int) f; };   //@ skip, default = "mkf"
Int closure(Int) mkf() { Int closure(Int) g = lambda(x) { x + 1 }; return g; }
Int main() {
    CS c = CS {.a = 1, .f = mkf()};
    Value v = to_value(c) else { VUnit };
    Result(CS, SerialError) back = from_value(v);
    Int n = match back { Ok(b) => b.f(b.a), Err(e) => -1 };
    println(f"{v} {n}");
    return 0;
}
RESID
run "skipped closure field" "$RD" --inplace closure_skip.resid
"$RESIDC" closure_skip.resid -o closure_skip --profile debug > build.txt 2>&1 || grep -v '^OK \|^note:\|^typecheck OK\|^wrote ' build.txt
./closure_skip

# Deriving only one side leaves the other a compile-time error.
cat > one_side.resid <<RESID
import "$SRC/serial.resid";
import "$SRC/value.resid";
//@ serial(encode)
type EO = { Int a; };
Int main() {
    Result(EO, SerialError) r = from_value(VInt(1));
    return 0;
}
RESID
"$RD" --inplace one_side.resid > /dev/null
echo "== decode of an encode-only type"
"$RESIDC" one_side.resid -o one_side --profile check > build.txt 2>&1
echo "exit $?"
grep -o 'no behavior instance Decode(EO,VDec)' build.txt | head -1

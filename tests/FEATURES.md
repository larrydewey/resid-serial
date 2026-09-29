# Feature coverage

Every public item and behavior of resid-serial, and the test that covers it.
Test programs are self-checking (`ok`/`FAIL` lines from `tests/check.resid`)
and `tests/run.sh` compares their full output, exit status included, with the
golden `.out` beside each. Check names below are the names in that output.

## Errors — `tests/errors.resid`

| Feature | Checks |
|---|---|
| `serial_error`, `custom_error`, `eof_error`, `syntax_error`, `invalid_type`, `invalid_value`, `invalid_length`, `unknown_field`, `missing_field`, `duplicate_field`, `unknown_variant`, `unsupported`, `trailing_input`: kind and exact message | one check each, named after the constructor |
| Expected-name lists of 0, 1, 2, 3, 4 names | `one_of 0` … `one_of 4`, `unknown_field` |
| `ErrorKind` (all 12) and `error_kind_name`, `Show(ErrorKind)` | `error kinds`, `Show(ErrorKind)` |
| `error_at`, `error_path`, `error_text` (with and without a path) | `error_path`, `error_text with path`, `error_path top level` |
| `at_field`, `at_index`, `at_key`, `at_variant`, `at_seg`: tag errors, pass `Ok` through, nest outermost first, keep the kind | `at_*` checks, `path keeps kind` |
| `Show(SerialError)`, `Peek` (all 15) and `Show(Peek)` | `Show(SerialError)`, `Show(Peek)` |

## Builtin instances — `tests/builtins.resid` (token format), `tests/formats/compact_test.resid` (positional format)

| Type | Encode tokens | Decode | Boundaries | Errors |
|---|---|---|---|---|
| `Bool` | `bool true/false` | same | — | `bool from Int` |
| `Int` | `int` | same | `int min`, `int max` | `int from Str` |
| `UInt(64)` | `u64 max`, `u64 zero` | same | both ends | `u64 from Int` |
| `Int(8/16/32)` | `i8/i16/i32 bounds` | same | both ends fit | one past each end: `i8 over/under` … |
| `UInt(8/16/32)` | `u8/u16/u32 bounds` | same | both ends fit | `u8/u16/u32 over`, `narrow wrong type` |
| `Int(128)`, `UInt(128)` | `i128 min/max`, `u128 max` | same | both ends | `i128 wrong type` |
| `Float`, `Float(32)`, `Float(16)` | `float`, `f32`, `f16` | same | — | `float wrong type` |
| `Dec(N)` | `dec` | `dec decode`, `dec decode integer text`, `dec rounds to N digits` | — | `dec bad text` (5 malformed texts), `is_decimal_text` |
| `Str`, `Str(N)` | `str`, `str unicode`, `Str(N)`, `Str(N) streams multibyte` (streamed from its storage) | `Str(N) fits` (into its own `StrBuf(N)`) | UTF-8 length: `utf8_len` | `Str(N) too long`, `Str(N) multibyte too long`, `Str(N) wrong type` |
| `Bytes(N)` | `Bytes(N)` (streamed) | `Bytes(N) short input pads` (into `BytesBuf(N)`) | at most N | `Bytes(N) too long`, `Bytes(N) not a byte`, `Bytes(N) wrong type` |
| `ByteBuf` / bytes | `bytes`, `empty bytes` | same | — | `bytes wrong type` |
| `Unit` | `unit` | same | — | `unit wrong type` |
| `Option(T)` | `none`, `some`, `some(none)` | same | — | `option wrong type`, `some missing payload` |
| `List(T)` | `list`, `empty list`, `nested list` | same | — | `list element path`, `nested list path`, `list unterminated`, `list wrong type` |
| `List(T, N)` | `List(T, N)`, `List(Str, N)` (element by element, in place) | same (into `ListBuf(T, N)`) | exact length | `List(T, N) short`, `List(T, N) long` |
| `Set(T)` | `set` (sorted), `set of str` | `set dedupes` | — | — |
| `Map(K, V)` | `map` (sorted keys), `empty map`, `map int keys` | `map duplicate key` (later wins) | — | `map value path` (keyed `["a"]`), `map key error`, `map wrong type` |
| `Result(T, E)` | `ok`, `err` | same | — | `result unknown variant`, `result unit variant`, `result payload path`, `result missing end` |
| Composition, top level | `deep composition`, `map of list of result` | — | — | `trailing input`, `empty input` |
| Everything through a positional format | `compact_test`: one round trip per builtin and derived shape, `positional layout` | | | `no untyped decoding`, `format-specific unsupported value`, `malformed input` |

Fixed-capacity values are never copied to a heap value: they stream from
their storage (`write_str_begin`/`write_str_char`, `write_bytes_begin`/
`write_byte`, per element) and decode into their own builders.

Not in the data model, so no instances (a use is a compile-time E0226):
`Int(256)`, `Int(512)`, `UInt(256)`, `UInt(512)`, `Float(128)`, `Vec(T, N)`,
the legacy NUL-terminated heap `Bytes` (use `ByteBuf` or `Bytes(N)`),
closures, handles.

## Entry points and helpers for hand-written instances — `tests/helpers.resid`, `tests/handwritten.resid`

| Feature | Checks |
|---|---|
| `encode_value`, `decode_value` (and its trailing-input check), `decode_next` (value streams) | `encode_value`, `decode_value`, `decode_value rejects trailing`, `decode_next` |
| Encode errors carry paths | `encode errors carry paths` |
| `parsed` | `parsed` |
| `write_struct1` / `read_struct1`: round trip, unknown field skipped, missing, duplicate, wrong name, value path | `write_struct1/read_struct1`, `read_struct1 …` (5) |
| `write_named`, `write_named_if` (writes / skips) | `write_named_if writes`, `write_named_if skips` |
| `write_entry`, `write_elem` | `write_entry`, `write_elem` |
| `write_unit_variant`, `write_newtype_variant`, `read_unit_payload`, `read_newtype_payload` and their mismatches | `unit variant`, `newtype variant`, `read_unit_payload on payload variant`, `read_newtype_payload on unit variant`, `payload errors carry the variant` |
| `require`, `or_default`, `flatten_opt`, `name_index`, `read_slot` (fills, duplicate, path), `skip_unknown` (skips, denies) | one check each |
| A full hand-written record and enum, both directions, through Value | `handwritten.resid` (golden) |

## Value — `tests/value.resid` (API), `tests/value_codec.resid` (encoder/decoder)

| Feature | Checks |
|---|---|
| All 16 `Value` variants; `ventry`, `vfield`, `vstruct`, `vtag`, `vvariant` | `show_value every variant`, `ventry/vfield/vtag fields` |
| `value_kind` (every variant), `show_value` / `Show(Value)` (every variant, floats keep `.0`, named/anonymous/empty structs, tagged/untagged variants) | `value_kind every variant`, `show_value every variant` |
| `value_eq` / `Eq(Value)`: reflexive, distinct, integers across widths and signs, huge u128, optional names, field order, variants, containers | `value_eq …` (8), `Eq(Value) ==` |
| `as_wide_int`, `as_wide_uint` | one check each |
| `value_field`, `value_field_in`, `get_field`, `get_field_or`, `get_field_in`, `get_field_in_or` (found, missing, wrong type with path) | one check each |
| `is_unit_value`, `flatten_fields` (struct, map, unit, errors), `without_fields` | one check each, `flatten_fields errors` |
| `split_internal_tag`, `split_adjacent_tag` and their errors; `write_internally_tagged` (struct, unit, non-struct error); `write_adjacent`, `write_adjacent_unit` | one check each |
| `Encode(Value, F)`: every variant's tokens | `Encode(Value) tokens` |
| `Decode(Value, F)`: every `Peek` kind, struct and variant names kept, end-marker error | `Decode(Value) …` (6) |
| `to_value` (`value_encoder`): identity on every variant, builtins, maps, results; every misuse (8 kinds) | `to_value …`, `to_value misuse` |
| `from_value` (`value_decoder`): integers across widths/signs and out of range, UInt paths, 128-bit paths, narrow ints, floats from integers, bool/str/unit, bytes from bytes or integer sequences (and bad bytes), lenient options, sequences, maps from maps or structs, variants from tags, strings and one-entry maps (and each error) | `Int from …`, `UInt paths`, `Int(128) paths`, `UInt(128) paths`, `narrow ints through Value`, `Float from integers`, `bool/str/unit`, `bytes paths`, `option paths`, `seq paths`, `map paths`, `map from struct`, `variant paths` |
| `read_skip`, `read_peek` (and at end), `read_end` (with input left), reads at end of input, `encodes_/decodes_human_readable` | `read_skip / read_peek`, `read_peek at end`, `read_end with input left`, `read at end`, `value_encoder/decoder is human readable` |

## Iterating and building — `tests/seq.resid`

| Feature | Checks |
|---|---|
| `Indexed(C, T)` for `List(T)`, `List(T, N)`, `Str` and `Str(N)` (code points), `Bytes(N)` | `Indexed …` (5) |
| `utf8_count`, `utf8_width` (every width) | `utf8_count / utf8_width` |
| `fold_items`, `all_items`, on empty sequences | `fold_items`, `all_items`, `empty sequences` |
| `Build(C, B, T)` for `List(T)`, `List(T, N)` (pads, overflows), `Str`, `Str(N)` (by bytes, whole code points), `Bytes(N)`, from empty; `build_from` between shapes | `Build …` (6) |
| The fixed builders directly: `push`, `push_char`, `finish`, `try_finish`, `discard`, nothing kept after an overflowing push, zero fill, `capacity()`, a generic empty fixed literal | `StrBuf(N) …`, `BytesBuf(N) try_finish`, `ListBuf(T, N) zero-fills`, `discard any builder`, `generic empty fixed literal` |
| Streaming through each format: Value (`to_value of fixed values`, `from_value into fixed values`, `pulling without begin`, stream misuse in `to_value misuse`), tokens (`streamed string is one Str token`, `streamed bytes are one Bytes token`, `stream misuse`, `pulling misuse`), positional (`streamed layouts equal whole ones`, `fixed overflow through a positional format`) | `value_codec`, `tokens`, `compact_test` |

## The token test format — `tests/tokens.resid`

| Feature | Checks |
|---|---|
| All 21 tokens: `show_token` / `Show(Token)`, `token_eq` / `Eq(Token)` including payload differences | `show_token every token`, `token_eq …` (3), `Eq(Token) ==` |
| `to_tokens`, human readable | `to_tokens`, `token encoder/decoder are human readable` |
| `read_skip` over every kind of value (10 shapes, nested), and unterminated | `read_skip every value kind`, `read_skip unterminated` |
| `read_peek` on every token, at end, struct names | `read_peek every value token`, `read_peek at end`, `read_peek struct name` |
| Struct names (mismatch, kept untyped), field/struct expectations | `struct name mismatch`, `untyped struct keeps its name`, `field expected`, `struct expected` |
| `read_variant_name` (enum, index, name, payload flag), wrong tokens | `read_variant_name`, `read_variant_name wrong token`, `read_variant_end wrong token` |
| `assert_ser_tokens`, `assert_de_tokens`, `assert_tokens`, `assert_de_error`: pass (used throughout) and every failure report | `assert_* reports …` (7), with the reports in the golden output |

## resid-derive — `tests/derive/`

| Feature | Where |
|---|---|
| Records, enums, generic records and enums, recursive types, `transparent`, all enum representations, `flatten` | `derive_test.resid` over `model.resid` |
| `default` zero values for every kind of field (16 types, fixed ones included) | `options_test`: `default zero values`, `defaults round trip when present` |
| `default = "fn"`, several `alias`es, `skip_encoding`, `skip_decoding`, `skip`, container `rename`, missing/duplicate via alias | `skip_encoding and skip_decoding on encode`, `default fns, aliases, skip_decoding on decode`, `missing field without default`, `an alias duplicating the field`, `container rename is the struct name` |
| `rename_all`: all 8 rules on fields and on variants; renamed variants decode by the new name only; `rename` beats `rename_all` | `rename_all fields`, `rename_all variants`, `renamed variants decode …`, `rename beats rename_all …` |
| `encode` / `decode` only (and the missing side is a compile error) | `encode only`, `decode only`; `cli.sh`: `decode of an encode-only type` |
| Generics: a parameter named `F`, two parameters, nested generic field types, generic `transparent`, empty record, generic tagged enum | `parameter named F`, `two parameters`, `nested generic field types`, `generic transparent`, `empty record`, `generic internally tagged` |
| `deny_unknown_fields` (with aliases) | `deny_unknown_fields`; `derive_test`: `user deny unknown` |
| `flatten`: two fields, a `Map` field, beside `skip_encoding_if`, any order, missing inner field, through tokens | `flatten …` (5) |
| `skip_encoding_if` (streaming and Value paths) | `derive_test`: `user ser …`, `user with email`; `flatten two fields, skip_encoding_if` |
| Externally tagged: newtype, unit, variant `alias`, variant `skip` (encode error, decode unknown), variants after a skipped one | `external newtype`, `variant alias`, `skipped variant`, `variants after a skipped one`; `derive_test` shape checks |
| Internally tagged: unit, struct, map, non-struct error, decode (any field order), missing/unknown tag, payload error path, through tokens | `internal …` (6) |
| Adjacently tagged: unit, newtype, renamed variant, missing content, unknown tag | `adjacent unit`, `adjacent newtype`, `adjacent decode` |
| Untagged: round trip of each kind, no fit, through tokens, skipped variant | `untagged …` (3), `skipped variant in another representation` |
| Annotation placement: line before a field, two lines, trailing on a field, after `};`, after a sum's `;`, multi-line sums; `pub type`; decoys in strings, comments and bodies ignored | `options.resid` (37 types found, decoys not) |
| Command line: no arguments, unknown option, missing file, `-o`, `--lib` with/without `/`, `--inplace` (append, idempotent, replace after an edit) | `cli.sh` transcript, `resid-derive --inplace is idempotent` |
| Diagnostics: closure field/payload, no zero value, unknown `rename_all` rule, unknown container/field/variant option, `tag` on a record, `transparent` on a sum, `transparent` with two fields, `content` without `tag`, `tag` without a name, `untagged` with `tag`, `deny_unknown_fields` with `flatten`, unterminated declaration, missing `;`, malformed unannotated declarations ignored | `cli.sh` transcript (one case each) |
| A skipped closure field compiles and keeps its default | `cli.sh`: `skipped closure field` |
| `--inplace` in a file with `main` | `inplace_app.resid` |

## Formats and scale

| Feature | Where |
|---|---|
| A non-self-describing format (fields by position, no peek/skip) | `formats/compact.resid`, `compact_test.resid` |
| 100k-element lists (Value, compact), 20k lists (tokens), 20k maps, nesting depth 2000, 100k non-ASCII code points of a `Str(N)` through every format, a recursive type's show | `scale.resid` |

## Documentation

| Feature | Where |
|---|---|
| Every example in `README.md` compiles and prints what the README says | `readme.resid` (derived region regenerated by `run.sh`) |

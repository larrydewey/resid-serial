# resid-serial

A serialization framework for [Resid](../resid), in the spirit of Rust's
serde: types describe themselves once, formats implement one protocol, and
any type goes to any format. This package is the framework only. It ships no
JSON, CBOR or other real formats; those are separate packages built on it.

```resid
import "serial.resid";
import "value.resid";

//@ serial(rename_all = "camelCase")
type User = { Str user_name; Option(Str) email; List(Int) scores; };

Int main() {
    User u = User {.user_name = "ann", .email = None, .scores = [3, 5]};
    Value v = to_value(u) else { VUnit };      // any format; Value is one
    println(f"{v}");                           // User { userName: "ann", email: None, scores: [3, 5] }
    Result(User, SerialError) back = from_value(v);
    println(f"{back}");
    return 0;
}
```

## How it fits together

| Piece | Role (serde equivalent) |
|---|---|
| `Encoder(F)` / `Decoder(F)` | what a **format** can write / read (`Serializer` / `Deserializer`) |
| `Encode(T, F)` / `Decode(T, F)` | how a **type** maps onto that protocol (`Serialize` / `Deserialize`), generic in the format `F` |
| `Parsed(T, F)` | a decoded value plus the format state after it |
| `SerialError` | errors with a kind, a message and a path (`.items[3].name`) |
| `Value` | a format-neutral tree (`serde_value`): `to_value`, `from_value` |
| `Indexed(C, T)` / `Build(C, B, T)` | iterate a sequence in place / build one through its linear builder |
| `tools/resid-derive` | generates `Encode`/`Decode` instances from `//@ serial` annotations (`#[derive]`) |
| `serial_test.resid` | a token format and `assert_tokens` (`serde_test`) |

Resid values never change, so a format's state is a value threaded through
every call: each verb takes the state and returns the next one, and `?`
carries the first error out.

```
Point --Encode(Point, F)--> write_struct_begin, write_field, ... --> F
F     --read_struct_begin, read_field, ...--Decode(Point, F)-->     Point
```

## Files

| File | Contents |
|---|---|
| `src/serial.resid` | errors, the protocols and type behaviors, entry points, helpers for hand-written instances, the builtin instances |
| `src/value.resid` | `Value`, its Show/Eq, `Encode(Value)`/`Decode(Value)`, the Value encoder and decoder, helpers for flattened and tagged representations |
| `src/seq.resid` | `Indexed` and `Build` with instances for lists, strings and the fixed-capacity types |
| `src/serial_test.resid` | the token format and assertions for testing instances |
| `tools/resid-derive.resid` | the instance generator |
| `tests/` | the test suite and `FEATURES.md`, the map from every feature to its test |

Import the files by path (`import "vendor/resid-serial/src/serial.resid";`)
or copy `src/` next to your code.

## The data model

serde's model, with Resid's types mapped onto it:

| Data model | Resid types |
|---|---|
| unit | `Unit` (`unit()`) |
| bool | `Bool` |
| int / uint (64-bit) | `Int`, `UInt(64)`; `Int(8/16/32)` and `UInt(8/16/32)` widen, and are range-checked on the way back (an error, not an abort) |
| i128 / u128 | `Int(128)`, `UInt(128)` |
| float | `Float`, `Float(32)`, `Float(16)` |
| string | `Str`, `Str(N)`, and `Dec(N)` as its decimal text |
| bytes | `ByteBuf` (a `List(Int)` of bytes), `Bytes(N)` |
| option | `Option(T)` |
| sequence | `List(T)`, `List(T, N)` (exactly N), `Set(T)` (sorted) |
| map | `Map(K, V)` (sorted by key) |
| struct | records |
| enum variant | sum types: unit variants, and variants with one payload; `Result(T, E)` is `Result { Ok(T), Err(E) }` |

`Int(256)`, `Int(512)`, `UInt(256)`, `UInt(512)`, `Float(128)`, `Vec(T, N)`,
closures and handles have no place in the model and no instances (using one is
the compile-time error E0226). The legacy NUL-terminated heap `Bytes` cannot
hold a zero byte; use `ByteBuf` or `Bytes(N)`.

The numeric instances are **one declaration per verb, generic in the width**, so
a width is never written out twice. `Carries` names the widths the model
carries, and the instance covers exactly those: a `UInt(16)` field works, a
`UInt(512)` one is a compile-time E0226 that says so rather than truncating.

```resid
behavior Carries(T) { Bool carried(); }        // the widths the model carries
@needs(Encoder(F), Carries(UInt(N)))
Result(F, SerialError) enc_uint(UInt(N) x, F s) { return write_uint(s, (UInt(64))x); }
Encode(UInt(N), F) = enc_uint;                  // every width Carries names
Encode(UInt(128), F) = enc_u128;                // the 128-bit verbs
```

**Fixed-capacity values are never copied to the heap.** `Str(N)`, `Bytes(N)`
and `List(T, N)` stream from their own storage (`write_str_char`,
`write_byte`, element by element) and decode into their own builders
(`StrBuf(N)`, `BytesBuf(N)`, `ListBuf(T, N)`), which report overflow as a
decode error.

## Writing instances

### Derived

Annotate the types and run the generator:

```resid
//@ serial(deny_unknown_fields)
type Config = {
    Str host;                     //@ rename = "hostname", alias = "server"
    Int port;                     //@ default = "default_port"
    Option(Str) note;             //@ skip_encoding_if = "is_none_str"
    Str secret;                   //@ skip, default
};

//@ serial(tag = "kind", rename_all = "snake_case")
type Event = Started(Config) | Stopped;
```

```sh
residc tools/resid-derive.resid -o resid-derive
./resid-derive --lib vendor/resid-serial/src types.resid     # writes types_serial.resid
./resid-derive --inplace app.resid                           # or into the file itself
```

The separate-file form imports your file, so the types' file must not import
the generated one; keep types in their own module or use `--inplace`.

Container options (in `serial(...)`):

| Option | Meaning |
|---|---|
| `encode` / `decode` | derive one side only |
| `rename = "Name"` | the name formats see |
| `rename_all = "rule"` | `lowercase`, `UPPERCASE`, `PascalCase`, `camelCase`, `snake_case`, `SCREAMING_SNAKE_CASE`, `kebab-case`, `SCREAMING-KEBAB-CASE` (serde's rules, for fields and for variants) |
| `deny_unknown_fields` | unknown struct fields are errors (not with `flatten`) |
| `transparent` | a one-field record encodes as its field |
| `tag = "t"` | enum: internally tagged, `{t: "Variant", ...fields}` |
| `tag = "t", content = "c"` | enum: adjacently tagged, `{t: "Variant", c: payload}` |
| `untagged` | enum: the payload alone; decoding tries the variants in order |

Field options: `rename`, `alias` (repeatable), `default` (the type's zero
value), `default = "fn"`, `skip`, `skip_encoding`, `skip_decoding`,
`skip_encoding_if = "fn"`, `flatten`. Variant options: `rename`, `alias`,
`skip`. An `Option` field that is absent decodes as `None`. Unknown options,
contradictory combinations and fields that cannot be encoded (closures without
`skip`) are reported with their line.

`flatten`, `tag` and `untagged` go through a `Value` when decoding, so, as in
serde, they need a self-describing format.

### By hand

The helpers keep hand-written instances short:

```resid
type Point = { Int x; Int y; };

@needs(Encoder(F))
Result(F, SerialError) enc_point(Point p, F s) {
    F s1 = write_struct_begin(s, "Point", 2)?;
    F s2 = write_named(s1, "x", p.x)?;
    F s3 = write_named(s2, "y", p.y)?;
    return write_struct_end(s3);
}
Encode(Point, F) = enc_point;
```

Only `Encoder(F)` is listed: `Encode(Int, F)` is covered by its instance for
every `F`. Decoding reads fields in any order into `Option` slots
(`read_slot` rejects duplicates, `require` reports missing ones, `or_default`
supplies defaults); `tests/handwritten.resid` shows a full record and enum.
For a quick decoder over a self-describing format, decode a `Value` and use
`get_field` / `get_field_or`.

## Writing a format

Implement `Encoder(F)` and/or `Decoder(F)` for your state type as a bundle
instance. The verbs bracket compound values and announce each part, so a
format can place separators and keys:

| Value | Encoder verbs | Decoder verbs |
|---|---|---|
| scalars | `write_unit`, `write_bool`, `write_int`, `write_uint`, `write_i128`, `write_u128`, `write_float`, `write_str`, `write_bytes` | `read_*` alike |
| streamed string / bytes | `write_str_begin(chars, bytes)`, `write_str_char`, `write_str_end`; `write_bytes_begin`, `write_byte`, `write_bytes_end` | `read_str_begin`, `read_str_next` (-1 at the end); `read_bytes_begin`, `read_bytes_next` |
| option | `write_none` / `write_some` + value | `read_option` |
| sequence | `write_seq_begin(len)`, `write_seq_elem` per element, `write_seq_end` | `read_seq_begin`, `read_seq_next` |
| map | `write_map_begin`, `write_map_key`, `write_map_value`, `write_map_end` | `read_map_begin`, `read_map_next`, `read_map_value` |
| struct | `write_struct_begin(name, len)`, `write_field(key)`, `write_struct_end` | `read_struct_begin(name, fields)`, `read_field(fields)` gives `KnownField(i)`, `UnknownField(name)` or `EndOfFields` |
| variant | `write_unit_variant`, or `write_variant_begin` + payload + `write_variant_end` | `read_variant` (or untyped `read_variant_name`), then `read_variant_unit` or `read_variant_payload` + payload + `read_variant_end` |
| untyped | — | `read_peek`, `read_skip` (self-describing formats; others return `unsupported(..)`) |
| top level | — | `read_end` rejects trailing input |

A positional format (one that stores no names) reports fields in declaration
order from `read_field`. `tests/formats/compact.resid` is a complete
positional format; `src/value.resid` (`VEnc`, `VDec`) and
`src/serial_test.resid` (`TokEnc`, `TokDec`) are self-describing ones.

## Testing instances

```resid
import "serial_test.resid";

Bool ok = assert_tokens(Point {.x = 1, .y = 2}, [
    TokStruct(struct_tok("Point", 2)),
    TokField("x"), TokInt(1), TokField("y"), TokInt(2),
    TokStructEnd
]);
```

`assert_ser_tokens`, `assert_de_tokens`, `assert_tokens` and
`assert_de_error` print what differed and return whether they passed.

## Requirements

resid-serial needs a Resid compiler with the changes made alongside it (in
`../resid`, spec v3.8): fixed-capacity builders, instance-covered needs,
expected types through `?`, `else` and `match` arms, hole-aware literals and
arms, generic sum constructors, two-slot 128-bit record fields, normalized
import paths, `capacity()` and integer widths read as values (§12, which is
what lets one instance serve every width of a number).

## Tests

```sh
tests/run.sh             # RESIDC=/path/to/residc to pick the compiler
tests/run.sh --update    # rewrite the golden .out files
```

Every test program checks its own results (`ok` / `FAIL` lines), and
`run.sh` compares each program's full output and exit status with its golden
file. `tests/FEATURES.md` maps every public function, verb, instance, derive
option and diagnostic to the checks that cover it.

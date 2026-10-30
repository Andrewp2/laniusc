# Generic indexed value in a Pair initializer

The first vector-edit admission compile rejected the generic deduplication
implementation before executing the program. At source hash `b4d6b253`, the
initializer contained:

```lanius
let values: core::pair::Pair<T,T> = core::pair::Pair {
    first: slots[self.length - 1], second: item
};
```

The compiler reported `LNC0006` at `first`: the indexed expression had unknown
type where generic parameter 0 was expected. The original diagnostic is in
`target/stdlib-work/vec-edit-admission-compile.log`.

The library now gives the indexed value an explicit `T` local before passing
it to the same initializer. This preserves operand order and ownership.

`inline.lani` and `typed_local.lani` are a confirmed standalone reduction/control
pair. Their imports, generic signature, concrete caller and assertions match;
the only semantic-neutral difference is the explicitly typed intermediate.
Both should compile and return zero. No compiler code is changed by this
dependency record.

## Executed controls

Root ran both controls with the preserved native Linux x86_64 compiler whose
SHA-256 begins `1c2718d4`:

| Fixture | SHA-256 prefix | Compile result | Native execution |
| --- | --- | --- | --- |
| `inline.lani` | `199eaaad` | Exit 1 in 3.969 s; `LNC0006` reports `first: values[index]` as unknown type where `T` is expected | Not run; compilation failed |
| `typed_local.lani` | `0a7c7f39` | Exit 0 in 3.382 s | Generated ELF exited 0 with empty stdout and stderr |

The result receipt is `target/stdlib-work/vec-edit-dependency-results.json`.
Compiler diagnostics are retained in
`target/stdlib-work/vec-edit-dependency-inline.stderr` and
`target/stdlib-work/vec-edit-dependency-typed_local.stderr`.

This isolates a generic indexed-expression typing limitation in a struct
initializer. It does not require a user-defined equality implementation, an
ownership trait, or a vector operation. Giving the indexed expression an
explicit `T` local is an executable workaround on this compiler snapshot.

Separately, the complete vector-edit admission passed on library source
`a5b93853` and fixture `20ea5b8b`: all five new APIs executed, with two matched
allocation/release pairs. The admission fixture's intervening `LNC0021` was a
missing required `PartialEq::partial_ne` method; completing that fixture trait
resolved it. It is not part of the compiler limitation isolated above.

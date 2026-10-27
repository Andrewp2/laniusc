# Ordinary nested-iteration negative admission

Status: all three negative-admission Rust tests passed. These invalid callers
of the actual stdlib `flatten` and `flat_map` helpers received the intended
source-local bound rejections. They do not implement another traversal engine
or fabricate an Infallible error value.

| Fixture | Accepted single invalid bound |
| --- | --- |
| `fallible_retirement.lani` | A real `InnerRetirement<Iter<i32>,u64>` cannot meet ordinary flatten's `InnerRetirement<Iter<i32>,core::clone_values::Infallible>` requirement. |
| `fallible_mapper.lani` | `Mapper<i32,Result<Iter<i32>,u64>>` cannot meet ordinary flat_map's `Mapper<i32,Iter<i32>>` requirement; its source, inner and actual Infallible retirement otherwise agree. |
| `wrong_inner_item.lani` | The selected `Iter<i32>` is not `Iterator<u64>`; source and actual Infallible retirement still agree on the exact inner type. |

Each caller explicitly declares its source, callback/policy, ordinary adapter
and all helper generic arguments. Each callback implementation is ordinary
valid source with a distinct receiver pattern. Infallible retirement in the
two controls truthfully consumes only a borrowed cursor with no owned backing;
there is no fake public API, extra borrowing trait or unsafe conversion.

The driver requires `LNC0008` (`TraitBoundUnsatisfied`), a primary label in the
particular fixture, and that label's source line containing the exact public
`core::iter::flatten<` or `core::iter::flat_map<` call. An earlier syntax,
visibility, implementation-header or constructor error is not accepted as the
desired bound rejection. Unexpected ELF emission also fails the test.

## Accepted receipt and provenance

`target/stdlib-work/infallible-nested-bounds-first.log` records **3 passed,
0 failed** in 4.77 seconds, following a 1.80-second test-profile build. Those
are separate build and test phases, not a measured whole-command duration.
The Rust binary was `stdlib_infallible_nested_bounds-7e98ef682debea67`.
All three exact `LNC0008` codes, fixture paths and public-helper source-line
checks passed on the unchanged driver, fixtures and imported core source:

| Accepted source | SHA-256 |
| --- | --- |
| `tests/stdlib_infallible_nested_bounds.rs` | `f1d5469efa1fa2337e312671ebae8c26235a574450f4c3921e78fe2b2ca482de` |
| `stdlib/core/iter.lani` | `5034fbac8a84b1499af18fbaf2963d54da4452e633413d33804b154e1a108a64` |
| `fallible_mapper.lani` | `b0edb2edbb59466c9d6b032e186642b9e1dacd1744b112fd40c054ebae7893a7` |
| `fallible_retirement.lani` | `34942ed2ae1f5b623685ce5dc89a00ea32f122151478338180c73b20241f84b4` |
| `wrong_inner_item.lani` | `c076b6f286929c9b83d743768b26727c5d0827f2663d0bcb569f881262f5aff7` |

This accepts the three selected compiler rejections only. No emitted Lanius
program was executed, and these tests establish no ordinary-adapter runtime,
ownership, native-resource or user-program target behavior. Positive executable
and resource evidence belongs to separate gates.

## Bounded commands

Root serializes actual compilation under the shared GPU lock. After driver
admission, a focused command bounded below two minutes is:

```sh
timeout --kill-after=2s 110s env \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test stdlib_infallible_nested_bounds -- --nocapture --test-threads=1
```

Exact filters:

- `ordinary_flatten_rejects_fallible_retirement`
- `ordinary_flat_map_rejects_fallible_mapper`
- `ordinary_flatten_rejects_wrong_inner_item`

No rerun or source correction was needed for this negative-admission receipt.

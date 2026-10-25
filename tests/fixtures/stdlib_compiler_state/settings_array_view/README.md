# Native aggregate array viewed as Text slice

Historical classification: compiler/code-generation dependency; no settings module or
configuration parser is imported. The native array and all literal backing
storage remain live through each call. Every element and view has an explicit
`core::text::Text` / `View<Text>` type. No owner is freed before use.

The four output lines compare the native array's direct element access,
a direct `View<Text> { values:path,start:1,length:2 }` initializer passed to a
function, an owned `alloc::vec<Text>.as_view()` passed to that function, and
`core::slice::view_range(path,1,2)` passed to the same function. Only the second
line is wrong. This isolates implicit array-to-slice conversion in a record
initializer; checked slice constructors accept the same live native array. Expected/observed stdout is saved alongside this file; the recorded
execution returned status 0 with empty stderr. Observed corruption is not a
supported settings policy, and the settings facade continues to accept valid
counted views. The application uses owned vectors for paths.

Original reproduction (x86_64 Linux; run from the repository root):

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
 timeout --kill-after=2s 60s target/stdlib-build/debug/laniusc \
 --stdlib-root stdlib --source-root extended \
 tests/fixtures/stdlib_compiler_state/settings_array_view/main.lani \
 -o target/stdlib-work/settings-array-view
timeout --kill-after=2s 100s target/stdlib-work/settings-array-view
```

Recorded 2026-10-23 at HEAD `d20ffacede28f22cedf7959fb2d54ca131ed0026` with
concurrent uncommitted work in the shared checkout. No compiler or runtime
changes were made by the settings provider.

SHA-256:

- `main.lani`: `ff781dcac2ba7ebec0eaee37bf7fd330ad4a95b275225fba51151d113c812afd`
- compiler `target/stdlib-build/debug/laniusc`: `665b4f7df83be4f44f9c404895d7f28efaeb3b227e1f0a3de630fc1e46962e92`
- produced ELF `target/stdlib-work/settings-array-view`: `9b1db27785559ed39a2fb709c4b380e7b4e9751e1a4332752392686ea0da10d0`

## Fresh baseline and repair

The exact source was reproduced again at
`d85be875a218b9eab7622d1cb8549ca0308ad4fc`, before the repair. It still returned
status 0, empty stderr and `6\n1241024840\n6\n6\n`. Its source hash and emitted
ELF hash matched the historical values above. The fresh compiler binary hash
was `51704757e738dfbf37d7ed3bc33fc976f7bf8348ab340d1f4068efbed58abfcf`;
the runtime shader set reported digest `a1a3dc017ab72950` (916 kernels).
The ignored snapshot `target/stdlib-work/array-slice-field-current-d85be875/`
retains that compiler, shader artifacts, stdlib sources, source entry, output,
and bounded reproduction script. A compiler binary alone does not pin this
compiler: it loads shader artifacts at runtime. For a fresh historical
reproduction, build the source at the baseline commit, including its shaders,
and run this unchanged entry with that commit's stdlib.

Record-field checking accepted the outer array-to-slice conversion but did not
retain its existing descriptor adjustment for lowering. Imported record
construction consequently copied the array's raw native width and used that
width to place following fields. Here `[Text;3]` occupies 15 native words;
the `values:[Text]` destination stores a three-word pointer/count/signed-stride
descriptor. Local declaration syntax had a separate conversion path, which
explains why simple local record controls worked.

The repair records the already accepted adjustment at each field value and
uses the captured descriptor's width for aggregate construction. It reuses
the existing snapshot and target lowering. The original array row retains
its storage layout and supplies the pointer and signed stride. There is no
new target, IR or ABI representation.

The unchanged `main.lani` is now an executable regression: all four paths
print `6`. The saved `observed.stdout` remains historical evidence.
`tests/codegen_array_slice_fields.rs` also runs `fields/main.lani`, covering
local and imported generic records, reordered named fields, leading and
following sentinels, packed positive and native negative strides, `i8`, `u64`,
mixed records, nested fixed arrays, empty arrays and zero-sized elements.
Factory views provide the controls for stride, live aliasing and logical
bounds. Three separate entries reject unrelated nominal element types,
different primitive element types and nested arrays of different extents
with `LNC0006`.

Focused verification after the repair:

- Four-way Text regression and three rejection entries passed in the initial
  focused invocation (the new layout fixture initially had a missing explicit
  count in its factory controls and did not compile).
- After correcting those control calls, the complete native layout fixture
  passed its exact test in 4.90 seconds.
- Existing `codegen_x86` tests `x86_wraps_fixed_array_as_slice_field` and
  `x86_wraps_fixed_array_in_nonfirst_slice_field` passed, 2/2 in 2.57 seconds.

The two changed shader kernels stay below their existing instruction budgets:
`compact_aggregate_requests` has 9,901 fully inlined instructions, up from
9,892 (+0.091%); `aggregate_elements` has 21,229, up from 20,904 (+1.555%).
Their SPIR-V sizes change from 41,824 to 41,992 bytes and from 154,780 to
155,836 bytes respectively. No local arrays or new resource bindings were added.

Run the focused regression after building it:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
 timeout --kill-after=2s 60s env \
 CARGO_TARGET_DIR=/home/andrew-peterson/code/laniusc/target/stdlib-build \
 CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
 cargo test --test codegen_array_slice_fields -- --nocapture --test-threads=1
```

# Native aggregate array viewed as Text slice

Classification: compiler/code-generation dependency; no settings module or
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

Reproduction (x86_64 Linux; run from the repository root):

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

This fixture is evidence, not a passing runtime test. Repair belongs to the
compiler owner; the passing vector control does not establish native-array
view correctness.
